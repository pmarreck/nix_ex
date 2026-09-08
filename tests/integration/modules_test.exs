defmodule NixEx.ModulesTest do
  use ExUnit.Case, async: true
  import NixEx.TestSupport

  test "generated modules agree with separate handwritten Nix and react to changed inputs" do
    nixpkgs = System.fetch_env!("NIX_EX_NIXPKGS")
    root = tmp!()
    out = Path.join(root, "generated")
    NixEx.Project.write(NixEx.Demo.files(), out)
    args = ["--arg", "nixpkgs", nixpkgs]
    golden = Path.expand("../fixtures/modules.nix", __DIR__)
    generated = Path.join(out, "default.nix")

    assert {~s({"enable":true,"greeting":"hello world","items":["first","last"],"priority":"forced"}),
            0} == eval_file(generated, args)

    assert eval_file(generated, args) == eval_file(golden, args)
    changed = args ++ ["--arg", "enabled", "false"]
    assert eval_file(generated, changed) == eval_file(golden, changed)
    refute eval_file(generated, changed) == eval_file(generated, args)
    assert {output, 0} = eval_file(generated, args ++ ["--argstr", "token", "Elixir"])
    assert output =~ "hello Elixir"
    {error, status} = eval_file(generated, args ++ ["--arg", "enabled", "42"])
    assert status != 0
    assert error =~ "boolean"
  end

  test "generated flake is consumable with Nix alone without a Nixpkgs bootstrap" do
    root = tmp!()
    out = Path.join(root, "flake")
    NixEx.Project.write(NixEx.Demo.files(), out)

    {value, status} =
      System.cmd(
        "nix",
        [
          "--extra-experimental-features",
          "nix-command flakes",
          "--offline",
          "eval",
          "--json",
          "path:#{out}#answer"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, value
    assert String.trim(value) == "42"
  end
end
