defmodule NixEx.MigrateTest do
  use ExUnit.Case, async: true
  import NixEx.TestSupport

  defp roundtrip(source) do
    root = tmp!()
    original = Path.join(root, "original.nix")
    File.write!(original, source)
    expression = NixEx.Migrate.from_file(original, root: root)
    elixir = NixEx.Migrate.to_elixir(expression)
    {regenerated, _} = Code.eval_string(elixir, [], file: "translated.exs")
    {expected, 0} = eval_file(original)
    assert eval!(regenerated) == expected
    elixir
  end

  test "migration preserves literals, escaping, interpolation and every binary operator family" do
    roundtrip(~S"""
    { text = ''
        hello ${toString (1 + 2)}
        shell ''${HOME}
      '';
      bools = [ (1 < 2) (2 <= 2) (3 > 2) (3 >= 3) (1 == 1) (1 != 2)
        (true && false) (true || false) (false -> false) (!false) ];
      values = [ null (-3) 1.25 (8 / 2) (3 * 2) (3 - 2) ];
      list = [1] ++ [2]; merged = {x=1;} // {x=2;};
    }
    """)
  end

  test "migration retains recursive bindings, curried functions and scope" do
    code =
      roundtrip(~S"""
      let fact = n: if n == 0 then 1 else n * fact (n - 1);
          custom-name = 40; unused = throw "unused";
      in { result = fact 6; answer = custom-name + 2; }
      """)

    refute code =~ "raw_nix"
    assert code =~ "nix do"
    roundtrip("let x=7; in rec { inherit x; y=x+1; }")
    roundtrip("with { x=7; }; assert x == 7; { value=x; }")
    roundtrip("({x}: let y=x+1; in y) {x=41;}")
  end

  test "ordinary module functions and scoped package lists emit readable DSL forms" do
    code =
      roundtrip(
        "({ lib, enabled ? true, ... }: with lib; if enabled then [answer] else []) {lib.answer=42;}"
      )

    assert code =~ "fn %{"
    assert code =~ "with_nix"
    refute code =~ "AST.node"
    code = roundtrip("let custom-name=42; in custom-name")
    refute code =~ "AST.node"
    assert code =~ "var("
  end

  test "migration preserves patterns, inheritance, dynamic attributes and fallbacks" do
    roundtrip(~S"""
    let f = { x ? 3, ... }@args: x + args.y;
        attr = "dynamic";
    in { result = f {y=4;}; set = { ${attr} = 9; inherit (builtins) nixVersion; };
         missing = {}.absent or 42; has = {a.b=1;} ? a.b; }
    """)
  end

  test "migration retains derivation identity without executing its builder" do
    roundtrip(~S"""
    (builtins.derivation {
      name = "migration-example";
      system = "x86_64-linux";
      builder = "/bin/sh";
      args = [ "-c" ''printf '%s' '${toString (6 * 7)}' > "$out"'' ];
    }).drvPath
    """)
  end

  test "migration retains forced failures and does not evaluate unused expressions" do
    root = tmp!()
    path = Path.join(root, "failure.nix")
    File.write!(path, "let unused = throw \"forced migration\"; in if false then 42 else unused")
    ast = NixEx.Migrate.from_file(path, root: root)
    {regenerated, _} = Code.eval_string(NixEx.Migrate.to_elixir(ast))
    assert_raise RuntimeError, ~r/forced migration/, fn -> eval!(regenerated) end
    File.write!(path, "{ invalid syntax")
    assert_raise ArgumentError, fn -> NixEx.Migrate.from_file(path, root: root) end
  end

  test "Nix identifiers that collide with Elixir syntax retain their bindings" do
    for name <-
          ~w(nil and not end after try rescue receive quote unquote cond case alias when do fn) do
      roundtrip("let #{name} = 42; in #{name}")
    end
  end

  test "migration rejects a source outside its declared relocation root" do
    root = tmp!()
    path = Path.join(root, "value.nix")
    File.write!(path, "42")

    assert_raise ArgumentError, ~r/inside.*root/, fn ->
      NixEx.Migrate.from_file(path, root: Path.join(root, "other"))
    end
  end

  test "the documented migration and regeneration commands work without the original source" do
    guide = File.read!(Path.expand("../../docs/MIGRATION.md", __DIR__))
    snippets = Regex.scan(~r/<!-- example: (\w+) -->\n```elixir\n(.*?)\n```/s, guide)
    assert Enum.map(snippets, &Enum.at(&1, 1)) == ["migrate", "regenerate"]
    code = Map.new(snippets, fn [_, name, source] -> {name, source} end)
    root = tmp!()
    original = Path.join(root, "existing-config")
    File.mkdir!(original)
    File.write!(Path.join(original, "default.nix"), "{answer=42;}")
    Code.eval_string(code["migrate"], [], file: Path.join(root, "migrate.exs"))
    File.rename!(original, Path.join(root, "original unavailable"))
    generator = Path.join(root, "elixir-config/generate.exs")
    File.write!(generator, code["regenerate"])
    output = Path.join(root, "output")
    assert {:ok, _} = NixEx.CLI.run(["generate", generator, output])
    assert {~s({"answer":42}), 0} == eval_file(Path.join(output, "default.nix"))
  end

  test "migrated files regenerate without the original expressions and survive relocation" do
    root = tmp!()
    source = Path.join(root, "source")
    File.mkdir!(source)
    File.write!(Path.join(source, "default.nix"), "import ./value { x=41; }")

    File.write!(
      Path.join(source, "value"),
      "{x}: { answer=x+1; text=builtins.readFile ./asset; }"
    )

    File.write!(Path.join(source, "asset"), "literal ${SHELL}")

    entries =
      Enum.map(["default.nix", "value"], fn name ->
        ast = NixEx.Migrate.from_file(Path.join(source, name), root: source)
        {expression, _} = Code.eval_string(NixEx.Migrate.to_elixir(ast))
        NixEx.Project.nix(name, expression)
      end)

    File.rename!(source, Path.join(root, "original unavailable"))
    output = Path.join(root, "generated tree")

    assert :ok =
             NixEx.Project.write(
               entries ++ [NixEx.Project.asset("asset", "literal ${SHELL}")],
               output
             )

    assert {~s({"answer":42,"text":"literal ${SHELL}"}), 0} ==
             eval_file(Path.join(output, "default.nix"))
  end

  test "a root reference from a nested expression still points at the project root" do
    root = tmp!()
    File.mkdir!(Path.join(root, "nested"))
    File.write!(Path.join(root, "nested/value.nix"), "builtins.readFile (../. + \"/asset\")")
    ast = NixEx.Migrate.from_file(Path.join(root, "nested/value.nix"), root: root)
    {expression, _} = Code.eval_string(NixEx.Migrate.to_elixir(ast))
    output = Path.join(tmp!(), "output")

    NixEx.Project.write(
      [
        NixEx.Project.nix("nested/value.nix", expression),
        NixEx.Project.asset("asset", "root asset")
      ],
      output
    )

    assert {~s("root asset"), 0} == eval_file(Path.join(output, "nested/value.nix"))
  end

  test "originally missing paths remain lazy missing paths rather than invented assets" do
    root = tmp!()
    path = Path.join(root, "default.nix")
    File.write!(path, "{ answer=42; missing=builtins.readFile ./absent; }")
    ast = NixEx.Migrate.from_file(path, root: root)
    {expression, _} = Code.eval_string(NixEx.Migrate.to_elixir(ast))
    output = Path.join(tmp!(), "output")
    NixEx.Project.write([NixEx.Project.nix("default.nix", expression)], output)
    assert {"42", 0} == eval_file(Path.join(output, "default.nix"), ["-A", "answer"])
    {error, status} = eval_file(Path.join(output, "default.nix"), ["-A", "missing"])
    assert status != 0
    assert error =~ "does not exist"
    refute File.exists?(Path.join(output, "absent"))
  end
end
