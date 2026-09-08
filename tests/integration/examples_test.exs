defmodule NixEx.ExamplesTest do
  use ExUnit.Case, async: true
  import NixEx.TestSupport

  @examples Path.expand("../../examples", __DIR__)

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
