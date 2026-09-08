defmodule NixEx.Expr do
  @moduledoc "A Nix syntax node. Construct nodes through NixEx.AST."
  defstruct [:op, :args, :origin]
end

defmodule NixEx.AST do
  @moduledoc "Explicit Nix syntax constructors. Values and function bodies are never evaluated here."
  alias NixEx.Expr
  @operators ~w(+ - * / ++ // == != < > <= >= && || ->)
  @reserved ~w(if then else assert with let in rec inherit or true false null)

  def node(op, args), do: %Expr{op: op, args: args}

  def var(name) when is_binary(name) do
    parts = String.split(name, ".")
    Enum.each(parts, &identifier!/1)

    case parts do
      [one] -> node(:var, one)
      [head | tail] -> select(var(head), tail)
    end
  end

  def identifier!(name) when is_atom(name), do: identifier!(Atom.to_string(name))

  def identifier!(name) when is_binary(name) do
    if Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_'\-]*$/, name) and name not in @reserved,
      do: name,
      else: raise(ArgumentError, "invalid Nix identifier: #{inspect(name)}")
  end

  def identifier!(name), do: raise(ArgumentError, "invalid Nix identifier: #{inspect(name)}")

  def attrs(bindings, opts \\ []),
    do: node(:attrs, {bindings, Keyword.get(opts, :recursive, false)})

  def let(bindings, body), do: node(:let, {bindings, body})
  def fn_(pattern, body), do: node(:fn, {pattern, body})
  def pattern(params, opts \\ []), do: node(:pattern, {params, opts})
  def call(fun, args), do: node(:call, {fun, args})
  def if_(condition, yes, no), do: node(:if, {condition, yes, no})
  def select(value, path), do: node(:select, {value, path, :no_default})
  def select(value, path, default), do: node(:select, {value, path, {:default, default}})
  def has(value, path), do: node(:has, {value, path})
  def op(operator, lhs, rhs) when operator in @operators, do: node(:op, {operator, lhs, rhs})

  def op(operator, _, _),
    do: raise(ArgumentError, "unsupported Nix operator: #{inspect(operator)}")

  def unary(operator, value) when operator in ["!", "-"], do: node(:unary, {operator, value})

  def unary(operator, _),
    do: raise(ArgumentError, "unsupported Nix unary operator: #{inspect(operator)}")

  def string(parts), do: node(:string, parts)
  def dynamic(value), do: node(:dynamic, value)
  def inherit_(names), do: node(:inherit, {nil, names})
  def inherit_(from, names), do: node(:inherit, {from, names})
  def with_(scope, body), do: node(:with, {scope, body})
  def assert_(condition, body), do: node(:assert, {condition, body})
  def import_(path), do: call(var("import"), [path])
  def import_(path, args), do: call(import_(path), [args])
  def ref(project_relative), do: node(:ref, project_relative)
  def source_path(relative), do: node(:source_path, relative)
  def absolute_path(path), do: node(:absolute_path, path)
  def raw_nix(source), do: node(:raw, source)

  def at(%Expr{} = expr, file, line) when is_binary(file) and is_integer(line) and line > 0,
    do: %{expr | origin: %{file: file, line: line}}
end
