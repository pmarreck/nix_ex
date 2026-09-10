defmodule NixEx.WorkflowTest do
  use ExUnit.Case, async: true
  import NixEx.TestSupport

  test "short command entry points expose help" do
    for command <- ["convert", "check", "import"] do
      assert {:ok, help} = NixEx.CLI.run([command, "--help"])
      assert help =~ "nix-ex COMMAND"
    end
  end

  test "convert accepts an expression or generator and check forces evaluation" do
    root = tmp!()
    script = Path.join(root, "my config.exs")
    File.write!(script, "import NixEx.DSL\nnix do: %{answer: 42}")
    assert {:ok, _} = NixEx.CLI.run(["convert", script])
    output = Path.join(root, "generated")
    assert {:ok, _} = NixEx.CLI.run(["check", output])
    File.write!(Path.join(output, "default.nix"), "throw \"check must force me\"")
    assert {:error, message} = NixEx.CLI.run(["check", output])
    assert message =~ "check must force me"
    assert {:error, _} = NixEx.CLI.run(["convert", script])
    assert File.read!(Path.join(output, "default.nix")) =~ "throw"
  end

  test "import converts a Nix file without overwriting an edited Elixir file" do
    root = tmp!()
    input = Path.join(root, "module with spaces.nix")
    File.write!(input, "{answer=42;}")
    assert {:ok, _} = NixEx.CLI.run(["import", input])
    elixir = input <> ".exs"
    assert File.read!(elixir) =~ "answer: 42"
    assert {:ok, _} = NixEx.CLI.run(["convert", elixir])
    assert {:ok, _} = NixEx.CLI.run(["import", input])
    File.write!(elixir, "edited")
    assert {:error, _} = NixEx.CLI.run(["import", input])
    assert File.read!(elixir) == "edited"
  end

  test "checking against an independent expression detects a changed result" do
    root = tmp!()
    a = Path.join(root, "a.nix")
    b = Path.join(root, "b.nix")
    File.write!(a, "builtins.trace \"expected diagnostic\" {answer=42;}")
    File.write!(b, "{answer=40+2;}")
    assert {:ok, _} = NixEx.CLI.run(["check", a, "--against", b])
    File.write!(b, "{answer=43;}")
    assert {:error, message} = NixEx.CLI.run(["check", a, "--against", b])
    assert message =~ "differ"
    File.write!(b, "x: x")
    assert {:error, _} = NixEx.CLI.run(["check", a, "--against", b])
  end

  test "standalone list expressions convert as Nix lists" do
    root = tmp!()
    script = Path.join(root, "list.exs")
    File.write!(script, "import NixEx.DSL\nnix do: [1, 2]")
    assert {:ok, _} = NixEx.CLI.run(["convert", script])
    assert {"[1,2]", 0} == eval_file(Path.join(root, "generated/default.nix"))
  end

  test "checks refuse import-from-derivation rather than running a builder" do
    root = tmp!()
    path = Path.join(root, "ifd.nix")

    derivation =
      ~S|builtins.derivation {name="check-must-not-build"; system="x86_64-linux"; builder="/does-not-exist";}|

    # Register the fixture's derivation without building it, so evaluation can
    # reach the IFD policy check rather than failing on an absent store record.
    assert {_, 0} = System.cmd("nix-instantiate", ["--expr", derivation], stderr_to_stdout: true)
    File.write!(path, "import (#{derivation})")
    assert {:error, message} = NixEx.CLI.run(["check", path])
    assert message =~ "allow-import-from-derivation"
  end

  test "import refuses destination symlinks and keeps the target unchanged" do
    root = tmp!()
    input = Path.join(root, "value.nix")
    protected = Path.join(root, "protected")
    File.write!(input, "42")
    File.write!(protected, "keep")
    File.ln_s!(protected, input <> ".exs")
    assert {:error, _} = NixEx.CLI.run(["import", input])
    assert File.read!(protected) == "keep"
  end

  test "irrelevant flags are rejected before conversion publishes output" do
    root = tmp!()
    source = Path.join(root, "generate.exs")
    File.write!(source, "42")
    assert {:error, message} = NixEx.CLI.run(["convert", source, "--against", "unused.nix"])
    assert message =~ "not valid for convert"
    refute File.exists?(Path.join(root, "generated"))
  end

  test "shell syntax in paths remains literal in the checker" do
    root = tmp!()
    file = Path.join(root, "literal $(printf injected).nix")
    File.write!(file, "42")
    assert {:ok, _} = NixEx.CLI.run(["check", file])
  end

  test "named project settings make generation and flake evaluation short" do
    root = tmp!()
    script = Path.join(root, "generate.exs")

    File.write!(script, ~S"""
    import NixEx.DSL
    [NixEx.Project.nix("flake.nix", nix do: %{outputs: fn %{self: self} -> %{answer: 42} end})]
    """)

    settings = Path.join(root, "nix-ex.exs")
    File.write!(settings, ~s([source: "generate.exs", output: "out", attribute: "answer"]))
    assert {:ok, _} = NixEx.CLI.run(["convert", "--project", settings])
    assert {:ok, _} = NixEx.CLI.run(["check", "--project", settings])

    File.write!(
      Path.join(root, "out/flake.nix"),
      "{outputs = {self}: {answer = throw \"forced flake error\";};}"
    )

    assert {:error, message} = NixEx.CLI.run(["check", "--project", settings])
    assert message =~ "forced flake error"
  end
end
