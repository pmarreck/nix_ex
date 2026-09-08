defmodule NixEx.Render do
  @moduledoc "Deterministic, parenthesized Nix rendering with explicit literal/interpolation boundaries."
  alias NixEx.{AST, Expr}

  def render(value, opts \\ []) do
    context = %{file: Keyword.get(opts, :file), outputs: Keyword.get(opts, :outputs)}
    emit(value, context) <> "\n"
  end

  defp emit(%Expr{origin: %{file: file, line: line}} = node, c) do
    safe_file = file |> String.replace("\n", " ") |> String.replace("\r", " ")
    "(\n# nix-ex source: #{safe_file}:#{line}\n" <> emit(%{node | origin: nil}, c) <> "\n)"
  end

  defp emit(%Expr{op: :var, args: name}, _), do: AST.identifier!(name)

  defp emit(%Expr{op: :attrs, args: {bindings, recursive}}, c),
    do: if(recursive, do: "rec ", else: "") <> "{\n" <> bindings(bindings, c) <> "}"

  defp emit(%Expr{op: :let, args: {bindings, body}}, c),
    do: "(let\n" <> bindings(bindings, c) <> "in " <> emit(body, c) <> ")"

  defp emit(%Expr{op: :fn, args: {param, body}}, c),
    do: "(" <> parameter(param, c) <> ": " <> emit(body, c) <> ")"

  defp emit(%Expr{op: :call, args: {fun, args}}, c) when is_list(args) and args != [],
    do: "(" <> Enum.map_join([fun | args], " ", &("(" <> emit(&1, c) <> ")")) <> ")"

  defp emit(%Expr{op: :if, args: {condition, yes, no}}, c),
    do: "(if #{emit(condition, c)} then #{emit(yes, c)} else #{emit(no, c)})"

  defp emit(%Expr{op: :select, args: {value, path, default}}, c) do
    fallback =
      case default do
        :no_default -> ""
        {:default, d} -> " or " <> emit(d, c)
      end

    "((#{emit(value, c)}).#{attrpath(path, c)}#{fallback})"
  end

  defp emit(%Expr{op: :has, args: {value, path}}, c),
    do: "(#{emit(value, c)} ? #{attrpath(path, c)})"

  defp emit(%Expr{op: :op, args: {op, lhs, rhs}}, c) do
    AST.op(op, lhs, rhs)
    "(#{emit(lhs, c)} #{op} #{emit(rhs, c)})"
  end

  defp emit(%Expr{op: :unary, args: {op, value}}, c) do
    AST.unary(op, value)
    "(#{op} (#{emit(value, c)}))"
  end

  defp emit(%Expr{op: :string, args: parts}, c) do
    "\"" <>
      Enum.map_join(parts, "", fn
        text when is_binary(text) -> escape(text)
        expression -> "${" <> emit(expression, c) <> "}"
      end) <> "\""
  end

  defp emit(%Expr{op: :with, args: {scope, body}}, c),
    do: "(with #{emit(scope, c)}; #{emit(body, c)})"

  defp emit(%Expr{op: :assert, args: {condition, body}}, c),
    do: "(assert #{emit(condition, c)}; #{emit(body, c)})"

  defp emit(%Expr{op: :ref, args: target}, c) do
    NixEx.Project.identity!(target)
    require_context!(c)
    require_target!(target, c.outputs)
    path(relative(Path.dirname(c.file), target))
  end

  defp emit(%Expr{op: :source_path, args: target}, c) when is_binary(target) do
    require_context!(c)

    if Path.type(target) != :relative or String.contains?(target, ["\\", <<0>>]),
      do: raise(ArgumentError, "expected source-relative path")

    resolved = Path.expand(target, Path.join("/project", Path.dirname(c.file)))

    unless resolved == "/project" or String.starts_with?(resolved, "/project/"),
      do: raise(ArgumentError, "source path escapes output tree")

    unless resolved == "/project",
      do: require_target!(String.replace_prefix(resolved, "/project/", ""), c.outputs)

    path(target)
  end

  defp emit(%Expr{op: :absolute_path, args: target}, _) when is_binary(target) do
    unless Path.type(target) == :absolute, do: raise(ArgumentError, "expected absolute path")
    "(/. + #{quote_string(target)})"
  end

  defp emit(%Expr{op: :raw, args: text}, _) when is_binary(text), do: "(#{text})"

  defp emit(%Expr{} = unknown, _),
    do: raise(ArgumentError, "unsupported Nix AST: #{inspect(unknown.op)}")

  defp emit(nil, _), do: "null"
  defp emit(true, _), do: "true"
  defp emit(false, _), do: "false"
  defp emit(-9_223_372_036_854_775_808, _), do: "(-9223372036854775807 - 1)"

  defp emit(n, _)
       when is_integer(n) and n >= -9_223_372_036_854_775_808 and n <= 9_223_372_036_854_775_807,
       do: if(n < 0, do: "(#{n})", else: Integer.to_string(n))

  defp emit(n, _) when is_float(n), do: "(#{Float.to_string(n)})"
  defp emit(text, _) when is_binary(text), do: quote_string(text)

  defp emit(values, c) when is_list(values),
    do: "[ " <> Enum.map_join(values, " ", &("(" <> emit(&1, c) <> ")")) <> " ]"

  defp emit(values, c) when is_map(values), do: emit(AST.attrs(values), c)
  defp emit(value, _), do: raise(ArgumentError, "unsupported Nix value: #{inspect(value)}")

  defp bindings(values, c) when is_map(values),
    do: bindings(Enum.sort_by(values, fn {k, _} -> to_string(k) end), c)

  defp bindings(values, c) when is_list(values) do
    entries =
      Enum.map(values, fn
        %Expr{op: :inherit, args: {from, names}} ->
          names = Enum.map(names, &AST.identifier!/1)
          scope = if from == nil, do: "", else: " (#{emit(from, c)})"
          {Enum.map(names, &[&1]), "inherit#{scope} #{Enum.join(names, " ")};\n"}

        {key, value} ->
          path = if is_list(key), do: key, else: [key]

          static =
            if Enum.all?(path, &(is_binary(&1) or is_atom(&1))),
              do: [Enum.map(path, &to_string/1)],
              else: []

          {static, "#{attrpath(path, c)} = #{emit(value, c)};\n"}

        value ->
          raise ArgumentError, "invalid Nix binding: #{inspect(value)}"
      end)

    keys = Enum.flat_map(entries, &elem(&1, 0))
    if length(Enum.uniq(keys)) != length(keys), do: raise(ArgumentError, "duplicate Nix binding")
    Enum.map_join(entries, "", &elem(&1, 1))
  end

  defp parameter(%Expr{op: :pattern, args: {params, opts}}, c) do
    names =
      Enum.map(params, fn
        {name, _} -> AST.identifier!(name)
        name -> AST.identifier!(name)
      end)

    if length(Enum.uniq(names)) != length(names),
      do: raise(ArgumentError, "duplicate function parameter")

    entries =
      Enum.map(params, fn
        {name, default} -> "#{AST.identifier!(name)} ? #{emit(default, c)}"
        name -> AST.identifier!(name)
      end)

    entries = if Keyword.get(opts, :ellipsis, false), do: entries ++ ["..."], else: entries

    at =
      case Keyword.get(opts, :at) do
        nil -> ""
        name -> "@" <> AST.identifier!(name)
      end

    "{ #{Enum.join(entries, ", ")} }#{at}"
  end

  defp parameter(name, _), do: AST.identifier!(name)

  defp attrpath(parts, c) when is_list(parts) and parts != [],
    do: Enum.map_join(parts, ".", &attr(&1, c))

  defp attrpath(_, _), do: raise(ArgumentError, "attribute path must be a nonempty list")
  defp attr(%Expr{op: :dynamic, args: value}, c), do: "${#{emit(value, c)}}"
  defp attr(name, _) when is_binary(name) or is_atom(name), do: quote_string(to_string(name))
  defp attr(name, _), do: raise(ArgumentError, "invalid attribute name: #{inspect(name)}")
  defp quote_string(text), do: "\"" <> escape(text) <> "\""

  defp escape(text) do
    unless String.valid?(text) and not String.contains?(text, <<0>>),
      do: raise(ArgumentError, "Nix strings require UTF-8 without NUL")

    text
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("${", "\\${")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp require_context!(%{file: nil}),
    do: raise(ArgumentError, "path references require an output file context")

  defp require_context!(_), do: :ok
  defp require_target!(_, nil), do: :ok

  defp require_target!(target, outputs) do
    unless MapSet.member?(outputs, target) or
             Enum.any?(outputs, &String.starts_with?(&1, target <> "/")),
           do: raise(ArgumentError, "missing project output: #{target}")
  end

  defp path(target), do: "(./. + #{quote_string("/" <> target)})"

  defp relative(from, to) do
    a = if from == ".", do: [], else: Path.split(from)
    b = Path.split(to)
    {a, b} = drop_common(a, b)
    Enum.join(List.duplicate("..", length(a)) ++ b, "/")
  end

  defp drop_common([h | a], [h | b]), do: drop_common(a, b)
  defp drop_common(a, b), do: {a, b}
end
