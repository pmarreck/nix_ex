defmodule NixEx.ExamplesTest do
  use ExUnit.Case, async: true
  import NixEx.TestSupport

  @examples Path.expand("../../examples", __DIR__)

  test "README Elixir examples compile and evaluate to their documented results" do
    readme = File.read!(Path.expand("../../README.md", __DIR__))
    snippets = Regex.scan(~r/<!-- example: (\w+) -->\n```elixir\n(.*?)\n```/s, readme)
    assert Enum.map(snippets, &Enum.at(&1, 1)) == ["quickstart", "options", "overlay", "advanced"]

    values =
      Map.new(snippets, fn [_, name, source] ->
        {value, _} = Code.eval_string(source, [], file: "README-#{name}.exs")
        {name, value}
      end)

    destination = Path.join(tmp!(), "readme")
    assert :ok = NixEx.Project.write(values["quickstart"], destination)

    assert {~s({"answer":42,"greeting":"hello Elixir"}), 0} ==
             eval_file(Path.join(destination, "default.nix"))

    alias NixEx.AST, as: N
    lib = N.import_(N.absolute_path(System.fetch_env!("NIX_EX_NIXPKGS") <> "/lib"))
    option = N.call(values["options"], [N.attrs(lib: lib)])
    assert eval!(N.select(option, ["options", "example", "enabled", "default"])) == "false"
    assert eval!(N.select(option, ["options", "example", "message", "default"])) == ~s("welcome")

    assert eval!(N.call(values["overlay"], [N.attrs(answer: 42), N.attrs(answer: 41)])) ==
             ~s({"answer":42,"description":"answer=42"})

    result = N.call(values["advanced"], [N.attrs([])])
    assert eval!(N.select(result, ["name"])) == ~s("Elixir")
    assert eval!(N.select(result, ["supplied"])) == "false"

    assert eval!(N.select(result, ["message"])) ==
             ~s("Hello, Elixir!\\nShell ${HOME} stays literal.\\n")
  end

  test "the demo and ordinary examples teach the quoted DSL without constructor boilerplate" do
    paths = [
      Path.expand("../../lib/nix_ex/demo.ex", __DIR__) | Path.wildcard(@examples <> "/*.exs")
    ]

    constructor_users =
      Enum.flat_map(paths, fn path ->
        syntax = path |> File.read!() |> Code.string_to_quoted!()

        {_, aliases} =
          Macro.prewalk(syntax, [], fn
            {:__aliases__, _, [:NixEx, :AST]} = node, found -> {node, [node | found]}
            node, found -> {node, found}
          end)

        if aliases == [], do: [], else: [Path.basename(path)]
      end)

    # This example deliberately teaches explicit source annotations through N.at.
    assert Enum.sort(constructor_users) == ["06_intentional_error.exs"]
  end

  # Run the public generator entry point; the real evaluator decides the result.
  defp generate!(name, root) do
    output = Path.join(root, name)
    script = Path.join(@examples, name <> ".exs")
    assert {:ok, _} = NixEx.CLI.run(["generate", script, output])
    output
  end

  test "macro example keeps branches lazy and evaluates recursive factorial" do
    output = generate!("01_macro_and_recursion", tmp!())
    assert {~s({"answer":42,"factorial":720}), 0} == eval_file(Path.join(output, "default.nix"))
  end

  test "multifile example reads its declared asset after relocation" do
    root = tmp!()
    output = generate!("02_imports_and_assets", root)
    relocated = Path.join(root, "relocated tree")
    File.rename!(output, relocated)

    assert {~s({"answer":42,"message":"hello ${USER}\\n"}), 0} ==
             eval_file(Path.join(relocated, "default.nix"))
  end

  test "module example uses the pinned module evaluator and responds to changed options" do
    output = generate!("03_module_merging", tmp!())
    file = Path.join(output, "default.nix")
    args = ["--arg", "nixpkgs", System.fetch_env!("NIX_EX_NIXPKGS")]

    assert {~s({"enabled":true,"message":"welcome","order":["first","last"]}), 0} ==
             eval_file(file, args)

    assert {~s({"enabled":false,"message":"disabled","order":["last"]}), 0} ==
             eval_file(file, args ++ ["--arg", "enabled", "false"])
  end

  test "overlay example retains a Nix fixed point without building a package" do
    output = generate!("04_overlay", tmp!())

    assert {~s({"answer":42,"description":"answer=42"}), 0} ==
             eval_file(Path.join(output, "default.nix"))
  end

  test "finite Stream example emits three modules and a Nix-only flake" do
    output = generate!("05_stream", tmp!())
    assert {"[10,20,30]", 0} == eval_file(Path.join(output, "default.nix"))

    {result, status} =
      System.cmd(
        "nix",
        [
          "--extra-experimental-features",
          "nix-command flakes",
          "--offline",
          "eval",
          "--json",
          "path:#{output}#values"
        ],
        stderr_to_stdout: true
      )

    assert {String.trim(result), status} == {"[10,20,30]", 0}
    assert File.regular?(Path.join(output, "values/3.nix"))
  end

  test "intentional-error example preserves Nix coordinates and a real Elixir origin line" do
    output = generate!("06_intentional_error", tmp!())
    file = Path.join(output, "default.nix")
    {error, status} = eval_file(file, ["--show-trace"])
    assert status != 0
    assert error =~ "example intentionally fails"
    assert error =~ "default.nix:"
    [_, line] = Regex.run(~r/nix-ex source: 06_intentional_error.exs:(\d+)/, File.read!(file))

    declaration =
      File.read!(Path.join(@examples, "06_intentional_error.exs"))
      |> String.split("\n")
      |> Enum.at(String.to_integer(line) - 1)

    assert declaration =~ "N.at("
  end
end
