defmodule NixEx.DSL do
  @moduledoc "A deliberately small quoted Elixir syntax subset. splice/1 explicitly executes host-stage code."

  defmacro nix(do: body), do: translate(body, __CALLER__)

  defp translate({:splice, _, [expression]}, _env), do: expression

  defp translate(value, _)
       when is_number(value) or is_binary(value) or is_boolean(value) or is_nil(value),
       do: Macro.escape(value)

  defp translate(values, env) when is_list(values), do: Enum.map(values, &translate(&1, env))

  defp translate({:%{}, meta, pairs} = syntax, env) do
    pairs =
      Enum.map(pairs, fn
        {k, v} when is_atom(k) or is_binary(k) -> {k, translate(v, env)}
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

  defp translate({:fn, meta, [{:->, _, [[{name, _, context}], body]}]}, env)
       when is_atom(context) do
    call(:fn_, [Atom.to_string(name), translate(body, env)], meta, env)
  end

  defp translate({:fn, meta, [{:->, _, [[{:%{}, _, pairs}], body]}]} = syntax, env) do
    names =
      Enum.map(pairs, fn
        {name, {name, _, context}} when is_atom(name) and is_atom(context) ->
          Atom.to_string(name)

        _ ->
          unsupported!(syntax, env)
      end)

    if length(Enum.uniq(names)) != length(names), do: unsupported!(syntax, env)
    pattern = quote do: NixEx.AST.pattern(unquote(names), ellipsis: true)
    call(:fn_, [pattern, translate(body, env)], meta, env)
  end

  # Quoted dots select Nix attributes; parentheses with arguments apply the value.
  # Translating the receiver recursively also handles attributes of call results.
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
    pairs = Enum.map(bindings, fn {k, v} -> {k, translate(v, env)} end)
    call(:let, [pairs, translate(body, env)], meta, env)
  end

  defp translate({:apply, meta, [fun, args]}, env) when is_list(args),
    do: call(:call, [translate(fun, env), translate(args, env)], meta, env)

  defp translate({:get, meta, [value, path]}, env) when is_list(path),
    do: call(:select, [translate(value, env), Macro.escape(path)], meta, env)

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

  # Elixir represents both trailing keywords and bracketed keywords as a list.
  # Only nonempty keyword lists in dotted-call argument positions become sets.
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
