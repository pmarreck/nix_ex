defmodule NixEx.Migrate do
  @moduledoc "One-time Nix-to-Elixir migration. Nix parses input; regeneration uses only emitted Elixir."
  alias NixEx.{AST, Expr}

  @operators %{
    "->" => 1,
    "||" => 2,
    "&&" => 3,
    "==" => 4,
    "!=" => 4,
    "<" => 5,
    ">" => 5,
    "<=" => 5,
    ">=" => 5,
    "//" => 6,
    "+" => 7,
    "-" => 7,
    "*" => 8,
    "/" => 8,
    "++" => 9
  }
  @stops ~w(in then else or)

  def from_file(path, opts \\ []) do
    path = Path.expand(path)
    root = Path.expand(Keyword.fetch!(opts, :root))

    unless String.starts_with?(path, root <> "/"),
      do: raise(ArgumentError, "source must be inside its relocation root")

    {source, status} =
      System.cmd("nix-instantiate", ["--parse", path], stderr_to_stdout: true)

    if status != 0, do: raise(ArgumentError, "Nix parsing failed for #{path}: #{source}")
    {expression, rest} = source |> lex([]) |> expression(0)

    if rest != [],
      do: raise(ArgumentError, "unconsumed normalized Nix syntax: #{inspect(Enum.take(rest, 6))}")

    parent = Path.dirname(Path.relative_to(path, root))

    root_reference =
      if parent == ".", do: ".", else: Enum.map_join(Path.split(parent), "/", fn _ -> ".." end)

    relocate(expression, {root, root_reference})
  end

  def to_elixir(expression) do
    source = "import NixEx.DSL\nnix do\n" <> dsl(expression) <> "\nend\n"
    source |> Code.format_string!() |> IO.iodata_to_binary() |> Kernel.<>("\n")
  end

  # Normalization removes comments and indented-string layout without evaluating
  # imports. This parser consumes that versioned output, never arbitrary raw text.
  defp lex("", acc), do: Enum.reverse(acc)
  defp lex(<<c, rest::binary>>, acc) when c in [32, 9, 10, 13], do: lex(rest, acc)

  defp lex(<<?", rest::binary>>, acc) do
    {parts, rest} = string(rest, [])

    token =
      if Enum.all?(parts, &is_binary/1),
        do: {:value, IO.iodata_to_binary(parts)},
        else: {:interpolated, AST.string(parts)}

    lex(rest, [token | acc])
  end

  defp lex(text, acc) do
    cond do
      match = Regex.run(~r/\A(?:\.\.\.|\$\{|->|\|\||&&|==|!=|<=|>=|\/\/|\+\+)/, text) ->
        [token] = match
        lex(drop(text, token), [token | acc])

      match = Regex.run(~r/\A\/(?:[^\s;(){}\[\]"=,+*?!<>]|\$)+/u, text) ->
        [path] = match
        lex(drop(text, path), [{:path, path} | acc])

      match = Regex.run(~r/\A[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/, text) ->
        [number] = match

        value =
          if String.contains?(number, [".", "e", "E"]),
            do: elem(Float.parse(number), 0),
            else: String.to_integer(number)

        lex(drop(text, number), [{:value, value} | acc])

      match = Regex.run(~r/\A[A-Za-z_][A-Za-z0-9_'\-]*/, text) ->
        [name] = match
        lex(drop(text, name), [{:id, name} | acc])

      true ->
        <<c, rest::binary>> = text

        if c not in ~c"(){}[];:,.=@?+-*/!<>",
          do: raise(ArgumentError, "unsupported normalized Nix token")

        lex(rest, [<<c>> | acc])
    end
  end

  defp drop(text, prefix),
    do: binary_part(text, byte_size(prefix), byte_size(text) - byte_size(prefix))

  defp string(<<?", rest::binary>>, acc) do
    parts =
      acc
      |> Enum.reverse()
      |> Enum.chunk_by(&is_binary/1)
      |> Enum.flat_map(fn
        [text | _] = chunk when is_binary(text) -> [IO.iodata_to_binary(chunk)]
        expressions -> expressions
      end)

    {parts, rest}
  end

  defp string("${" <> rest, acc) do
    {source, rest} = interpolation(rest, 1, [])
    {value, []} = source |> lex([]) |> expression(0)
    string(rest, [value | acc])
  end

  defp string(<<?\\, c, rest::binary>>, acc) do
    value =
      case c do
        ?n -> "\n"
        ?r -> "\r"
        ?t -> "\t"
        _ -> <<c>>
      end

    string(rest, [value | acc])
  end

  defp string(<<c, rest::binary>>, acc), do: string(rest, [<<c>> | acc])
  defp string("", _), do: raise(ArgumentError, "unterminated normalized string")

  defp interpolation("}" <> rest, 1, acc),
    do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp interpolation("}" <> rest, depth, acc), do: interpolation(rest, depth - 1, ["}" | acc])
  defp interpolation("{" <> rest, depth, acc), do: interpolation(rest, depth + 1, ["{" | acc])

  defp interpolation(<<?", text::binary>>, depth, acc) do
    {_, rest} = string(text, [])
    consumed = binary_part(text, 0, byte_size(text) - byte_size(rest))
    interpolation(rest, depth, ["\"" <> consumed | acc])
  end

  defp interpolation(<<c, rest::binary>>, depth, acc),
    do: interpolation(rest, depth, [<<c>> | acc])

  defp interpolation("", _, _), do: raise(ArgumentError, "unterminated normalized interpolation")

  defp expression(tokens, minimum) do
    {left, rest} = prefix(tokens)
    tail(left, rest, minimum)
  end

  defp prefix([{:value, value} | rest]), do: {value, rest}
  defp prefix([{:interpolated, value} | rest]), do: {value, rest}
  defp prefix([{:path, path} | rest]), do: {AST.absolute_path(path), rest}
  defp prefix([{:id, "true"} | rest]), do: {true, rest}
  defp prefix([{:id, "false"} | rest]), do: {false, rest}
  defp prefix([{:id, "null"} | rest]), do: {nil, rest}

  defp prefix([{:id, "if"} | rest]) do
    {condition, rest} = expression(rest, 0)
    {yes, rest} = expression(expect(rest, {:id, "then"}), 0)
    {no, rest} = expression(expect(rest, {:id, "else"}), 0)
    {AST.if_(condition, yes, no), rest}
  end

  defp prefix([{:id, "let"} | rest]) do
    {bindings, rest} = bindings(rest, {:id, "in"}, [])
    {body, rest} = expression(rest, 0)
    {AST.let(bindings, body), rest}
  end

  defp prefix([{:id, word} | rest]) when word in ["with", "assert"] do
    {scope, rest} = expression(rest, 0)
    {body, rest} = expression(expect(rest, ";"), 0)
    node = if word == "with", do: AST.with_(scope, body), else: AST.assert_(scope, body)
    {node, rest}
  end

  defp prefix([{:id, "rec"}, "{" | rest]) do
    {bindings, rest} = bindings(rest, "}", [])
    {AST.attrs(bindings, recursive: true), rest}
  end

  defp prefix([{:id, name}, ":" | rest]) do
    {body, rest} = expression(rest, 0)
    {AST.fn_(name, body), rest}
  end

  defp prefix([{:id, name} | rest]), do: {AST.var(name), rest}

  defp prefix(["(" | rest]) do
    {value, rest} = expression(rest, 0)
    {value, expect(rest, ")")}
  end

  defp prefix(["[" | rest]), do: elements(rest, [])

  defp prefix(["{" | rest]) do
    if pattern_tail?(after_brace(rest, 1)) do
      {params, rest, ellipsis} = parameters(rest, [], false)

      {at, rest} =
        case rest do
          ["@", {:id, name} | tail] -> {name, tail}
          _ -> {nil, rest}
        end

      {body, rest} = expression(expect(rest, ":"), 0)
      {AST.fn_(AST.pattern(params, ellipsis: ellipsis, at: at), body), rest}
    else
      {bindings, rest} = bindings(rest, "}", [])
      {AST.attrs(bindings), rest}
    end
  end

  defp prefix(["!" | rest]) do
    {value, rest} = expression(rest, 11)
    {AST.unary("!", value), rest}
  end

  defp prefix(tokens),
    do:
      raise(ArgumentError, "unsupported normalized expression: #{inspect(Enum.take(tokens, 6))}")

  defp tail(left, ["." | rest], minimum) when minimum <= 13 do
    {path, rest} = attrpath(rest)

    {value, rest} =
      case rest do
        [{:id, "or"} | rest] ->
          {fallback, rest} = expression(rest, 0)
          {AST.select(left, path, fallback), rest}

        _ ->
          {AST.select(left, path), rest}
      end

    tail(value, rest, minimum)
  end

  defp tail(left, ["?" | rest], minimum) when minimum <= 10 do
    {path, rest} = attrpath(rest)
    tail(AST.has(left, path), rest, minimum)
  end

  defp tail(left, [op | rest] = tokens, minimum) do
    precedence = Map.get(@operators, op)

    cond do
      precedence != nil and precedence >= minimum ->
        {right, rest} =
          expression(rest, precedence + if(op in ["->", "//", "++"], do: 0, else: 1))

        tail(AST.op(op, left, right), rest, minimum)

      minimum <= 11 and argument?(op) ->
        {right, rest} = expression(tokens, 12)
        tail(AST.call(left, [right]), rest, minimum)

      true ->
        {left, tokens}
    end
  end

  defp tail(left, [], _), do: {left, []}
  defp argument?({:id, name}), do: name not in @stops
  defp argument?({:value, _}), do: true
  defp argument?({:interpolated, _}), do: true
  defp argument?({:path, _}), do: true
  defp argument?(token), do: token in ["(", "[", "{"]

  defp elements(["]" | rest], acc), do: {Enum.reverse(acc), rest}

  defp elements(tokens, acc) do
    {value, rest} = expression(tokens, 12)
    elements(rest, [value | acc])
  end

  defp bindings([ending | rest], ending, acc), do: {Enum.reverse(acc), rest}

  defp bindings([{:id, "inherit"} | rest], ending, acc) do
    {scope, rest} =
      case rest do
        ["(" | _] -> expression(rest, 12)
        _ -> {nil, rest}
      end

    {names, rest} = inherited(rest, [])
    value = if scope == nil, do: AST.inherit_(names), else: AST.inherit_(scope, names)
    bindings(rest, ending, [value | acc])
  end

  defp bindings(tokens, ending, acc) do
    {path, rest} = attrpath(tokens)
    {value, rest} = expression(expect(rest, "="), 0)
    bindings(expect(rest, ";"), ending, [{path, value} | acc])
  end

  defp inherited([";" | rest], acc), do: {Enum.reverse(acc), rest}
  defp inherited([{:id, name} | rest], acc), do: inherited(rest, [name | acc])
  defp inherited(tokens, _), do: raise(ArgumentError, "unsupported inherit: #{inspect(tokens)}")

  defp attrpath(tokens) do
    {name, rest} = attribute(tokens)

    case rest do
      ["." | tail] ->
        {names, rest} = attrpath(tail)
        {[name | names], rest}

      _ ->
        {[name], rest}
    end
  end

  defp attribute([{:id, name} | rest]), do: {name, rest}
  defp attribute([{:value, name} | rest]) when is_binary(name), do: {name, rest}
  defp attribute([{:interpolated, value} | rest]), do: {AST.dynamic(value), rest}

  defp attribute(["${" | rest]) do
    {value, rest} = expression(rest, 0)
    {AST.dynamic(value), expect(rest, "}")}
  end

  defp attribute(tokens),
    do: raise(ArgumentError, "unsupported attribute: #{inspect(Enum.take(tokens, 6))}")

  defp parameters(["}" | rest], acc, ellipsis), do: {Enum.reverse(acc), rest, ellipsis}
  defp parameters(["," | rest], acc, ellipsis), do: parameters(rest, acc, ellipsis)
  defp parameters(["..." | rest], acc, _), do: parameters(rest, acc, true)

  defp parameters([{:id, name}, "?" | rest], acc, ellipsis) do
    {default, rest} = expression(rest, 0)
    parameters(rest, [{name, default} | acc], ellipsis)
  end

  defp parameters([{:id, name} | rest], acc, ellipsis),
    do: parameters(rest, [name | acc], ellipsis)

  defp parameters(tokens, _, _),
    do: raise(ArgumentError, "unsupported function pattern: #{inspect(tokens)}")

  defp after_brace(["}" | rest], 1), do: rest
  defp after_brace(["}" | rest], depth), do: after_brace(rest, depth - 1)

  defp after_brace([open | rest], depth) when open in ["{", "${"],
    do: after_brace(rest, depth + 1)

  defp after_brace([_ | rest], depth), do: after_brace(rest, depth)
  defp after_brace([], _), do: raise(ArgumentError, "unclosed attribute set")
  defp pattern_tail?([token | _]), do: token in [":", "@"]
  defp pattern_tail?([]), do: false
  defp expect([token | rest], token), do: rest

  defp expect(tokens, token),
    do: raise(ArgumentError, "expected #{inspect(token)}, got #{inspect(Enum.take(tokens, 4))}")

  defp relocate(%Expr{op: :absolute_path, args: path}, {root, root_reference}) do
    if path == root or String.starts_with?(path, root <> "/") do
      relative = Path.relative_to(path, root)

      cond do
        relative == "." -> AST.source_path(root_reference)
        File.exists?(path) -> AST.ref(relative)
        true -> AST.op("+", AST.source_path(root_reference), "/" <> relative)
      end
    else
      AST.absolute_path(path)
    end
  end

  defp relocate(%Expr{} = expr, root), do: %{expr | args: relocate(expr.args, root)}
  defp relocate(values, root) when is_list(values), do: Enum.map(values, &relocate(&1, root))

  defp relocate(tuple, root) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&relocate(&1, root)) |> List.to_tuple()

  defp relocate(value, _), do: value

  defp dsl(%Expr{op: :var, args: name}) do
    if safe_name?(name),
      do: name,
      else: "var(#{inspect(name)})"
  end

  defp dsl(%Expr{op: :attrs, args: {bindings, recursive}}) do
    if Enum.all?(bindings, &match?({[_], _}, &1)) do
      keywords = Enum.all?(bindings, &match?({[name], _} when is_binary(name), &1))

      map =
        "%{" <>
          Enum.map_join(bindings, ",\n", fn {[key], value} ->
            if(keywords, do: inspect(key) <> ": ", else: attribute_source(key) <> " => ") <>
              dsl(value)
          end) <> "}"

      if recursive, do: "rec(#{map})", else: map
    else
      name = if recursive, do: "rec", else: "attrs"
      "#{name} do\n#{binding_source(bindings)}\nend"
    end
  end

  defp dsl(%Expr{op: :let, args: {bindings, body}}) do
    if Enum.all?(bindings, fn
         {[name], _} -> is_binary(name)
         _ -> false
       end) do
      "let [" <>
        Enum.map_join(bindings, ",\n", fn {[name], value} ->
          inspect(name) <> ": " <> dsl(value)
        end) <> "] do\n" <> dsl(body) <> "\nend"
    else
      "let do\n#{binding_source(bindings)}\n#{dsl(body)}\nend"
    end
  end

  defp dsl(%Expr{op: :fn, args: {name, body}}) when is_binary(name) do
    "fn #{dsl(AST.var(name))} -> #{dsl(body)} end"
  end

  defp dsl(%Expr{op: :fn, args: {%Expr{op: :pattern, args: {params, opts}}, body}} = expr) do
    if Keyword.get(opts, :at) == nil or safe_name?(Keyword.get(opts, :at)) do
      fields =
        Enum.map_join(params, ", ", fn
          {name, default} -> "#{inspect(name)}: #{dsl(AST.var(name))} \\\\ (#{dsl(default)})"
          name -> "#{inspect(name)}: #{dsl(AST.var(name))}"
        end)

      pattern = "%{#{fields}}"
      pattern = if Keyword.get(opts, :ellipsis, false), do: pattern, else: "exact(#{pattern})"
      pattern = if opts[:at], do: "#{opts[:at]} = #{pattern}", else: pattern
      "fn #{pattern} ->\n#{dsl(body)}\nend"
    else
      escape(expr)
    end
  end

  defp dsl(%Expr{op: :call} = expr) do
    {fun, args} = application(expr, [])

    arguments =
      case args do
        [%Expr{op: :attrs, args: {[_ | _] = bindings, false}}] ->
          if Enum.all?(bindings, &match?({[name], _} when is_binary(name), &1)),
            do:
              Enum.map_join(bindings, ", ", fn {[name], value} ->
                "#{inspect(name)}: #{dsl(value)}"
              end),
            else: Enum.map_join(args, ", ", &dsl/1)

        _ ->
          Enum.map_join(args, ", ", &dsl/1)
      end

    case fun do
      %Expr{op: :var, args: "import"} when length(args) in [1, 2] ->
        "import_nix(#{arguments})"

      %Expr{op: :select, args: {_, path, :no_default}} ->
        if Enum.all?(path, &safe_name?/1),
          do: "#{dsl(fun)}(#{arguments})",
          else: "(#{dsl(fun)}).(#{arguments})"

      _ ->
        "(#{dsl(fun)}).(#{arguments})"
    end
  end

  defp dsl(%Expr{op: :with, args: {scope, body}}),
    do: "with_nix #{dsl(scope)} do\n#{dsl(body)}\nend"

  defp dsl(%Expr{op: :assert, args: {condition, body}}),
    do: "assert_nix #{dsl(condition)} do\n#{dsl(body)}\nend"

  defp dsl(%Expr{op: :select, args: {value, path, :no_default}}) do
    if Enum.all?(path, &safe_name?/1),
      do: "(" <> dsl(value) <> ")." <> Enum.join(path, "."),
      else: "get(#{dsl(value)}, #{path_source(path)})"
  end

  defp dsl(%Expr{op: :select, args: {value, path, {:default, default}}}),
    do: "get(#{dsl(value)}, #{path_source(path)}, #{dsl(default)})"

  defp dsl(%Expr{op: :has, args: {value, path}}),
    do: "has?(#{dsl(value)}, #{path_source(path)})"

  defp dsl(%Expr{op: :string, args: parts}) do
    multiline =
      Enum.any?(parts, &(is_binary(&1) and String.contains?(&1, "\n"))) and
        is_binary(List.last(parts)) and String.ends_with?(List.last(parts), "\n")

    content =
      Enum.map_join(parts, fn
        text when is_binary(text) ->
          escape = fn piece ->
            piece |> inspect(printable_limit: :infinity) |> String.slice(1..-2//1)
          end

          if multiline do
            text
            |> String.split("\n")
            |> Enum.map_join("\n", fn piece ->
              piece
              |> escape.()
              |> String.replace("\\\"", "\"")
              |> String.replace("\"\"\"", "\\\"\"\"")
            end)
          else
            escape.(text)
          end

        expr ->
          "\#{" <> dsl(expr) <> "}"
      end)

    if multiline, do: "~n\"\"\"\n" <> content <> "\"\"\"", else: "~n\"" <> content <> "\""
  end

  defp dsl(%Expr{op: :if, args: {condition, yes, no}}),
    do: "if #{dsl(condition)} do\n#{dsl(yes)}\nelse\n#{dsl(no)}\nend"

  defp dsl(%Expr{op: :op, args: {op, left, right}} = expr) do
    cond do
      op == "+" and string_left?(left) -> dsl(AST.string(string_parts(expr)))
      op == "//" -> "Map.merge(#{dsl(left)}, #{dsl(right)})"
      op == "->" -> escape(expr)
      true -> "(#{dsl(left)} #{op} #{dsl(right)})"
    end
  end

  defp dsl(%Expr{op: :unary, args: {op, value}}), do: "#{op}(#{dsl(value)})"

  defp dsl(%Expr{op: op, args: path}) when op in [:ref, :source_path],
    do: "#{op}(#{inspect(path)})"

  defp dsl(%Expr{} = expr), do: escape(expr)
  defp dsl(values) when is_list(values), do: "[" <> Enum.map_join(values, ",\n", &dsl/1) <> "]"
  defp dsl(value), do: inspect(value, limit: :infinity, printable_limit: :infinity)
  defp application(%Expr{op: :call, args: {fun, args}}, rest), do: application(fun, args ++ rest)
  defp application(fun, args), do: {fun, args}

  defp string_left?(value) when is_binary(value), do: true
  defp string_left?(%Expr{op: :op, args: {"+", left, _}}), do: string_left?(left)
  defp string_left?(_), do: false
  defp string_parts(%Expr{op: :op, args: {"+", left, right}}), do: string_parts(left) ++ [right]
  defp string_parts(value), do: [value]

  defp attribute_source(%Expr{op: :dynamic, args: value}), do: dsl(value)
  defp attribute_source(value), do: inspect(value)
  defp path_source(path), do: "[" <> Enum.map_join(path, ", ", &attribute_source/1) <> "]"

  defp binding_source(bindings) do
    Enum.map_join(bindings, "\n", fn
      %Expr{op: :inherit, args: {nil, names}} ->
        "inherit(" <>
          Enum.map_join(names, ", ", fn name ->
            if safe_name?(name), do: name, else: inspect(name)
          end) <> ")"

      %Expr{op: :inherit, args: {scope, names}} ->
        "inherit(#{dsl(scope)}, #{inspect(names)})"

      {[name], value} when is_binary(name) ->
        "#{dsl(AST.var(name))} = #{dsl(value)}"

      {[%Expr{op: :dynamic} = key], value} ->
        "%{#{attribute_source(key)} => #{dsl(value)}}"

      {path, value} ->
        if Enum.all?(path, &safe_name?/1),
          do: "#{Enum.join(path, ".")} = #{dsl(value)}",
          else: raise(ArgumentError, "unsupported binding path for Elixir migration")
    end)
  end

  defp safe_name?(name) when is_binary(name),
    do:
      Regex.match?(~r/^[a-z_][a-zA-Z0-9_]*$/, name) and
        name not in ~w(fn do end after catch rescue when alias import case cond try receive quote unquote true false nil and or not in else)

  defp safe_name?(_), do: false

  defp escape(%Expr{op: op, args: args}),
    do: "splice(NixEx.AST.node(#{inspect(op)}, #{data(args)}))"

  defp data(%Expr{} = expr), do: "(nix do\n#{dsl(expr)}\nend)"
  defp data(values) when is_list(values), do: "[" <> Enum.map_join(values, ", ", &data/1) <> "]"

  defp data(tuple) when is_tuple(tuple),
    do: "{" <> (tuple |> Tuple.to_list() |> Enum.map_join(", ", &data/1)) <> "}"

  defp data(value), do: inspect(value, limit: :infinity, printable_limit: :infinity)
end
