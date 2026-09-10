defmodule NixEx.DSL do
  @moduledoc "A deliberately small quoted Elixir syntax subset. splice/1 explicitly executes host-stage code."

  defmacro nix(do: body), do: translate(body, __CALLER__)

  defp translate({:splice, _, [expression]}, _env), do: expression

  defp translate(value, _)
       when is_number(value) or is_binary(value) or is_boolean(value) or is_nil(value),
       do: Macro.escape(value)

  defp translate(values, env) when is_list(values), do: Enum.map(values, &translate(&1, env))

  defp translate({:<<>>, meta, parts}, env),
    do: call(:string, [Enum.map(parts, &string_part(&1, env))], meta, env)

  defp translate({:sigil_n, meta, [{:<<>>, _, parts}, []]}, env),
    do: call(:string, [Enum.map(parts, &nix_string_part(&1, env))], meta, env)

  defp translate({name, meta, [[do: body]]}, env) when name in [:attrs, :rec] do
    call(:attrs, [binding_block(body, env), [recursive: name == :rec]], meta, env)
  end

  defp translate({:rec, meta, [{:%{}, _, _} = map]}, env),
    do: call(:attrs, [binding_block(map, env), [recursive: true]], meta, env)

  defp translate({:let, meta, [[do: body]]}, env) do
    statements = statements(body)
    bindings = Enum.drop(statements, -1)

    call(
      :let,
      [binding_block({:__block__, [], bindings}, env), translate(List.last(statements), env)],
      meta,
      env
    )
  end

  defp translate({name, meta, [path]}, env) when name in [:ref, :source_path],
    do: call(name, [translate(path, env)], meta, env)

  defp translate({:var, meta, [name]}, env) when is_binary(name),
    do: call(:var, [name], meta, env)

  defp translate({name, meta, [scope, [do: body]]}, env)
       when name in [:with_nix, :assert_nix] do
    constructor = if name == :with_nix, do: :with_, else: :assert_
    call(constructor, [translate(scope, env), translate(body, env)], meta, env)
  end

  defp translate({:import_nix, meta, args}, env) when length(args) in [1, 2],
    do: call(:import_, Enum.map(args, &call_argument(&1, meta, env)), meta, env)

  defp translate({:%{}, meta, pairs} = syntax, env) do
    pairs =
      Enum.map(pairs, fn
        {k, v} -> {[attribute(k, env)], translate(v, env)}
        _ -> unsupported!(syntax, env)
      end)

    call(:attrs, [pairs], meta, env)
  end

  defp translate({:if, meta, [condition, clauses]} = syntax, env) do
    unless Keyword.keyword?(clauses) and Enum.sort(Keyword.keys(clauses)) == [:do, :else],
      do: unsupported!(syntax, env)

    call(
      :if_,
      Enum.map(
        [condition, Keyword.fetch!(clauses, :do), Keyword.fetch!(clauses, :else)],
        &translate(&1, env)
      ),
      meta,
      env
    )
  end

  defp translate({:fn, meta, [{:->, _, [args, body]}]} = syntax, env)
       when is_list(args) and args != [] do
    parameters = Enum.map(args, &parameter(&1, env))
    names = Enum.flat_map(parameters, &elem(&1, 1))
    if length(Enum.uniq(names)) != length(names), do: unsupported!(syntax, env)

    Enum.reduce(Enum.reverse(parameters), translate(body, env), fn {parameter, _}, result ->
      call(:fn_, [parameter, result], meta, env)
    end)
  end

  defp translate({{:., _, [fun]}, meta, args}, env) when is_list(args) and args != [],
    do:
      call(:call, [translate(fun, env), Enum.map(args, &call_argument(&1, meta, env))], meta, env)

  defp translate({:|>, _, [value, target]} = syntax, env) do
    piped =
      try do
        Macro.pipe(value, target, 0)
      rescue
        ArgumentError -> unsupported!(syntax, env)
      end

    translate(piped, env)
  end

  # Quoted dots select Nix attributes; parentheses with arguments apply the value.
  # Translating the receiver recursively also handles attributes of call results.
  defp translate({{:., _, [{:__aliases__, _, [:Map]}, :merge]}, meta, [left, right]}, env),
    do:
      call(
        :op,
        ["//", call_argument(left, meta, env), call_argument(right, meta, env)],
        meta,
        env
      )

  defp translate({{:., _, [{:__aliases__, _, _}, _]}, _, _} = syntax, env),
    do: unsupported!(syntax, env)

  defp translate({{:., _, [receiver, name]}, meta, args} = syntax, env)
       when is_atom(name) and is_list(args) do
    if args == [] and not Keyword.get(meta, :no_parens, false),
      do: unsupported!(syntax, env)

    selection = call(:select, [translate(receiver, env), [Atom.to_string(name)]], meta, env)

    case args do
      [] -> selection
      _ -> call(:call, [selection, Enum.map(args, &call_argument(&1, meta, env))], meta, env)
    end
  end

  defp translate({:let, meta, [bindings, [do: body]]} = syntax, env) when is_list(bindings) do
    unless Keyword.keyword?(bindings), do: unsupported!(syntax, env)
    pairs = Enum.map(bindings, fn {k, v} -> {Atom.to_string(k), translate(v, env)} end)
    call(:let, [pairs, translate(body, env)], meta, env)
  end

  defp translate({:apply, meta, [fun, args]}, env) when is_list(args),
    do: call(:call, [translate(fun, env), translate(args, env)], meta, env)

  defp translate({:get, meta, [value, path]}, env) when is_list(path),
    do: call(:select, [translate(value, env), Enum.map(path, &attribute(&1, env))], meta, env)

  defp translate({:get, meta, [value, path, default]}, env) when is_list(path),
    do:
      call(
        :select,
        [translate(value, env), Enum.map(path, &attribute(&1, env)), translate(default, env)],
        meta,
        env
      )

  defp translate({:has?, meta, [value, path]}, env) when is_list(path),
    do: call(:has, [translate(value, env), Enum.map(path, &attribute(&1, env))], meta, env)

  defp translate({:throw, meta, [message]}, env),
    do:
      call(
        :call,
        [quote(do: NixEx.AST.var("builtins.throw")), [translate(message, env)]],
        meta,
        env
      )

  defp translate({op, meta, [lhs, rhs]}, env)
       when op in [:+, :-, :*, :/, :++, :==, :!=, :<, :>, :<=, :>=, :&&, :||],
       do: call(:op, [Atom.to_string(op), translate(lhs, env), translate(rhs, env)], meta, env)

  defp translate({op, meta, [value]}, env) when op in [:!, :-],
    do: call(:unary, [Atom.to_string(op), translate(value, env)], meta, env)

  defp translate({name, meta, context}, env) when is_atom(name) and is_atom(context),
    do: call(:var, [Atom.to_string(name)], meta, env)

  defp translate(unknown, env), do: unsupported!(unknown, env)

  # Only the parser's interpolation form is accepted, not arbitrary bitstrings.
  # Conversion happens in Nix so interpolated variables and failures stay lazy.
  defp string_part(text, _env) when is_binary(text), do: text

  defp string_part(
         {:"::", meta, [{{:., _, [Kernel, :to_string]}, _, [value]}, {:binary, _, _}]},
         env
       ),
       do:
         call(
           :call,
           [quote(do: NixEx.AST.var("builtins.toString")), [translate(value, env)]],
           meta,
           env
         )

  defp string_part(syntax, env), do: unsupported!(syntax, env)

  defp nix_string_part(text, _) when is_binary(text), do: Macro.unescape_string(text)

  defp nix_string_part(
         {:"::", _, [{{:., _, [Kernel, :to_string]}, _, [value]}, {:binary, _, _}]},
         env
       ),
       do: translate(value, env)

  defp nix_string_part(syntax, env), do: unsupported!(syntax, env)

  defp attribute(name, _) when is_atom(name), do: Atom.to_string(name)
  defp attribute(name, _) when is_binary(name), do: name
  defp attribute(expression, env), do: call(:dynamic, [translate(expression, env)], [], env)

  defp statements({:__block__, _, expressions}), do: expressions
  defp statements(expression), do: [expression]

  defp binding_block(body, env) do
    groups =
      Enum.map(statements(body), fn
        {:inherit, meta, [scope, names]} when is_list(names) ->
          names = Enum.map(names, &inherit_name(&1, env))
          [call(:inherit_, [translate(scope, env), names], meta, env)]

        {:inherit, meta, names} ->
          [call(:inherit_, [Enum.map(names, &inherit_name(&1, env))], meta, env)]

        {:%{}, _, pairs} ->
          Enum.map(pairs, fn {key, value} -> {[attribute(key, env)], translate(value, env)} end)

        {:=, _, [key, value]} ->
          [{binding_path(key, env), translate(value, env)}]

        syntax ->
          unsupported!(syntax, env)
      end)

    Enum.concat(groups)
  end

  defp inherit_name(name, _) when is_atom(name), do: Atom.to_string(name)
  defp inherit_name(name, _) when is_binary(name), do: name

  defp inherit_name({name, _, context}, _) when is_atom(name) and is_atom(context),
    do: Atom.to_string(name)

  defp inherit_name(syntax, env), do: unsupported!(syntax, env)

  defp binding_path({name, _, context}, _) when is_atom(name) and is_atom(context),
    do: [Atom.to_string(name)]

  defp binding_path({:var, _, [name]}, _) when is_binary(name), do: [name]

  defp binding_path({{:., _, [parent, name]}, _, []}, env),
    do: binding_path(parent, env) ++ [Atom.to_string(name)]

  defp binding_path(syntax, env), do: unsupported!(syntax, env)

  # Keep argument names explicit so repeated Elixir patterns cannot silently
  # become shadowing Nix parameters when a multi-argument function is curried.
  defp parameter({name, _, context}, _env) when is_atom(name) and is_atom(context),
    do: {Atom.to_string(name), [name]}

  defp parameter({:var, _, [name]}, _) when is_binary(name), do: {name, [String.to_atom(name)]}

  defp parameter({:=, _, [{name, _, context}, argument]} = syntax, env)
       when is_atom(name) and is_atom(context) do
    unless match?({:%{}, _, _}, argument) or match?({:exact, _, [_]}, argument),
      do: unsupported!(syntax, env)

    {pattern, names} = parameter(argument, env)

    value =
      quote do
        %NixEx.Expr{args: {params, opts}} = unquote(pattern)
        NixEx.AST.pattern(params, Keyword.put(opts, :at, unquote(Atom.to_string(name))))
      end

    {value, [name | names]}
  end

  defp parameter({:exact, _, [{:%{}, _, _} = map]}, env), do: map_parameter(map, env, false)
  defp parameter({:%{}, _, _} = map, env), do: map_parameter(map, env, true)
  defp parameter(syntax, env), do: unsupported!(syntax, env)

  defp map_parameter({:%{}, _, pairs} = syntax, env, ellipsis) do
    params =
      Enum.map(pairs, fn
        {name, {:var, _, [bound]}} when is_atom(name) and is_binary(bound) ->
          unless Atom.to_string(name) == bound, do: unsupported!(syntax, env)
          bound

        {name, {:\\, _, [{:var, _, [bound]}, default]}} when is_atom(name) and is_binary(bound) ->
          unless Atom.to_string(name) == bound, do: unsupported!(syntax, env)
          {bound, translate(default, env)}

        {name, {name, _, context}} when is_atom(name) and is_atom(context) ->
          Atom.to_string(name)

        {name, {:\\, _, [{name, _, context}, default]}}
        when is_atom(name) and is_atom(context) ->
          {Atom.to_string(name), translate(default, env)}

        _ ->
          unsupported!(syntax, env)
      end)

    pattern = quote do: NixEx.AST.pattern(unquote(params), ellipsis: unquote(ellipsis))
    {pattern, Enum.map(pairs, &elem(&1, 0))}
  end

  # Elixir represents both trailing keywords and bracketed keywords as a list.
  # Only nonempty keyword lists in call argument positions become sets.
  defp call_argument(value, meta, env) when is_list(value) and value != [] do
    if Keyword.keyword?(value),
      do: translate({:%{}, meta, value}, env),
      else: translate(value, env)
  end

  defp call_argument(value, _meta, env), do: translate(value, env)

  defp unsupported!(unknown, env) do
    meta = if is_tuple(unknown) and tuple_size(unknown) == 3, do: elem(unknown, 1), else: []

    raise CompileError,
      file: env.file,
      line: Keyword.get(meta, :line, env.line),
      description:
        "unsupported nix syntax: #{Macro.to_string(unknown)}; use AST constructors through splice/1"
  end

  defp call(name, args, meta, env) do
    file = Path.basename(env.file)
    line = Keyword.get(meta, :line, env.line)
    expression = {{:., [], [NixEx.AST, name]}, [], args}
    quote do: NixEx.AST.at(unquote(expression), unquote(file), unquote(line))
  end
end
