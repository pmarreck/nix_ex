defmodule NixEx.ProjectTest do
  use ExUnit.Case, async: true
  alias NixEx.AST, as: N
  alias NixEx.Project, as: P
  import NixEx.TestSupport

  test "nested imports, extensionless expressions, directory defaults and assets relocate" do
    root = tmp!()

    expression =
      N.attrs(
        answer: N.call(N.import_(N.ref("modules/value")), [N.attrs(x: 41)]),
        directory: N.import_(N.ref("packages")),
        text: N.call(N.var("builtins.readFile"), [N.ref("assets/a ${literal} space.txt")])
      )

    files = [
      P.nix("default.nix", expression),
      P.nix("modules/value", N.fn_(N.pattern(["x"]), N.op("+", N.var("x"), 1))),
      P.nix("packages/default.nix", N.import_(N.source_path("../other.nix"))),
      P.nix("other.nix", 17),
      P.asset("assets/a ${literal} space.txt", "hello ${SHELL}\n")
    ]

    a = Path.join(root, "first")
    assert :ok == P.write(files, a)

    assert {~s({"answer":42,"directory":17,"text":"hello ${SHELL}\\n"}), 0} ==
             eval_file(Path.join(a, "default.nix"))

    assert :ok == P.write(Enum.reverse(files), a)
    b = Path.join(root, "relocated space")
    File.rename!(a, b)
    assert elem(eval_file(Path.join(b, "default.nix")), 1) == 0
  end

  test "validation failures leave no partial output and preserve unrelated destinations" do
    root = tmp!()
    out = Path.join(root, "out")

    for bad <- ["../escape", "/absolute", "a/../b", "a//b", "./b", "", "a\\b"] do
      assert_raise ArgumentError, fn -> P.write([P.asset(bad, "bad")], out) end
      refute File.exists?(out)
    end

    assert_raise ArgumentError, fn ->
      P.write([P.asset("same", "a"), P.asset("same", "b")], out)
    end

    assert_raise ArgumentError, fn -> P.write([P.asset("a", "a"), P.asset("a/b", "b")], out) end
    assert_raise ArgumentError, fn -> P.write([P.nix("default.nix", N.ref("missing"))], out) end

    assert_raise ArgumentError, fn ->
      P.write([P.nix("default.nix", N.source_path("../outside"))], out)
    end

    refute File.exists?(out)
    File.mkdir!(out)
    File.write!(Path.join(out, "keep"), "valuable")
    assert_raise ArgumentError, fn -> P.write([P.asset("new", "new")], out) end
    assert File.read!(Path.join(out, "keep")) == "valuable"
    refute File.exists?(Path.join(out, "new"))
  end

  test "broad destinations are rejected without scanning their contents" do
    for destination <- ["/", System.user_home!()] do
      assert_raise ArgumentError, ~r/broad destination/, fn -> P.destination!(destination) end
    end
  end

  test "symlinks, changed files, modes and extra outputs fail the regeneration check" do
    root = tmp!()
    out = Path.join(root, "generated")
    entries = [P.asset("script", "contents", mode: 0o755)]
    P.write(entries, out)
    assert P.check(entries, out)
    File.chmod!(Path.join(out, "script"), 0o644)
    refute P.check(entries, out)
    File.chmod!(Path.join(out, "script"), 0o755)
    File.write!(Path.join(out, "extra"), "keep")
    refute P.check(entries, out)
    assert_raise ArgumentError, fn -> P.write(entries, out) end
    link = Path.join(root, "link")
    File.ln_s!(out, link)
    assert_raise ArgumentError, fn -> P.write(entries, link) end
    assert_raise ArgumentError, fn -> P.write(entries, Path.join(link, "child")) end
  end

  test "Stream only delays generation and is fully consumed before publishing" do
    root = tmp!()
    out = Path.join(root, "stream")
    me = self()

    stream =
      Stream.map(1..3, fn n ->
        send(me, {:generated, n})
        P.nix("#{n}.nix", n)
      end)

    refute_received {:generated, _}
    assert :ok == P.write(stream, out)
    for n <- 1..3, do: assert_received({:generated, ^n})

    broken =
      Stream.map(1..3, fn
        3 -> raise "generator failure"
        n -> P.nix("#{n}.nix", n)
      end)

    assert_raise RuntimeError, "generator failure", fn ->
      P.write(broken, Path.join(root, "broken"))
    end

    refute File.exists?(Path.join(root, "broken"))
  end

  test "source-relative project root and asset path interpolation remain paths" do
    root = tmp!()
    out = Path.join(root, "tree")

    expr =
      N.attrs(
        root: N.call(N.var("builtins.baseNameOf"), [N.source_path(".")]),
        nested: N.import_(N.ref("nested/check.nix")),
        asset: N.string([N.ref("asset.txt")])
      )

    entries = [
      P.nix("default.nix", expr),
      P.asset("asset.txt", "payload"),
      P.nix("nested/check.nix", N.call(N.var("builtins.baseNameOf"), [N.source_path("..")]))
    ]

    P.write(entries, out)
    {value, 0} = eval_file(Path.join(out, "default.nix"))
    assert value =~ ~s("root":"tree")
    assert value =~ ~s("nested":"tree")
    assert value =~ "/nix/store/"
  end

  test "Nix runtime failure names generated file with an origin route in its source" do
    root = tmp!()
    out = Path.join(root, "origins")
    bad = N.at(N.call(N.var("builtins.throw"), ["origin check"]), "example.exs", 17)
    P.write([P.nix("failure.nix", bad)], out)
    file = Path.join(out, "failure.nix")
    {error, status} = eval_file(file, ["--show-trace"])
    assert status != 0
    assert error =~ "failure.nix"
    assert error =~ "origin check"
    assert File.read!(file) =~ "nix-ex source: example.exs:17"
  end
end
