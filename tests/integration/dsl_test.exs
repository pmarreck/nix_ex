defmodule NixEx.DSLTest do
  use ExUnit.Case, async: true
  import NixEx.TestSupport

  defp quoted!(source, bindings \\ []) do
    {expression, _} =
      Code.eval_string("import NixEx.DSL\nnix do\n" <> source <> "\nend", bindings,
        file: "ergonomics.exs"
      )

    expression
  end

  test "dotted access retains function values and arbitrary lexical namespaces" do
    expression =
      quoted!(~S"""
      let [tools: %{nested: %{answer: 41}}, increment: fn x -> x + 1 end] do
        let [custom: %{run: increment}, tools: %{nested: %{answer: 6}}] do
          %{called: custom.run(tools.nested.answer), selected: apply(custom.run, [41])}
        end
      end
      """)

    assert eval!(expression) == ~s({"called":7,"selected":42})

    assert_raise RuntimeError, ~r/undefined variable 'lib'/, fn ->
      eval!(quoted!("lib.mkOption(default: false)"))
    end
  end

  test "dotted calls curry positional arguments and keep unused arguments lazy" do
    assert eval!(quoted!("builtins.add(19, 23)")) == "42"

    expression =
      quoted!(~S"""
      let [custom: %{ignore: fn unused -> 42 end}] do
        custom.ignore(builtins.throw("forced dotted call"))
      end
      """)

    assert eval!(expression) == "42"

    assert_raise RuntimeError, ~r/forced dotted call/, fn ->
      eval!(quoted!(~s|builtins.add(1, builtins.throw("forced dotted call"))|))
    end
  end

  test "keyword call arguments are sets while empty and ordinary lists remain lists" do
    for source <- [
          "builtins.getAttr(\"answer\", answer: 42)",
          "builtins.getAttr(\"answer\", %{answer: 42})",
          "builtins.getAttr(\"answer\", [answer: 42])"
        ] do
      assert eval!(quoted!(source)) == "42"
    end

    assert eval!(quoted!("builtins.length([])")) == "0"
    assert eval!(quoted!("builtins.length([10, 20, 30])")) == "3"
    assert eval!(quoted!("builtins.attrNames(%{})")) == "[]"
    assert eval!(quoted!("builtins.getAttr(\"items\", items: [1, 2])")) == "[1,2]"
  end

  test "module map patterns accept extra arguments and require their named arguments" do
    module =
      quoted!(~S"""
      fn %{lib: lib, config: config} ->
        %{answer: lib.add(config.value, 2)}
      end
      """)

    alias NixEx.AST, as: N
    arguments = N.attrs(lib: N.var("builtins"), config: N.attrs(value: 40), extra: true)
    assert eval!(N.call(module, [arguments])) == ~s({"answer":42})

    assert_raise RuntimeError, ~r/required argument/, fn ->
      eval!(N.call(module, [N.attrs(lib: N.var("builtins"))]))
    end

    assert eval!(N.call(quoted!("fn %{} -> 42 end"), [N.attrs(extra: true)])) == "42"
  end

  test "mkOption and nested type calls work against pinned Nixpkgs" do
    expression =
      quoted!(
        ~S"""
        let [lib: splice(NixEx.AST.import_(NixEx.AST.absolute_path(nixpkgs <> "/lib")))] do
          let [option: lib.mkOption(type: lib.types.bool, default: false)] do
            %{
              default: option.default,
              valid: option.type.check(true),
              invalid: option.type.check("true"),
              list_valid: lib.types.listOf(lib.types.str).check(["first", "last"]),
              list_invalid: lib.types.listOf(lib.types.str).check("not a list")
            }
          end
        end
        """,
        nixpkgs: System.fetch_env!("NIX_EX_NIXPKGS")
      )

    assert eval!(expression) ==
             ~s({"default":false,"invalid":false,"list_invalid":false,"list_valid":true,"valid":true})
  end

  test "dotted expressions preserve their originating source line" do
    expression = quoted!("builtins.add(19, 23)")
    assert expression.origin == %{file: "ergonomics.exs", line: 3}
  end

  test "unsupported calls and patterns fail at the Elixir source location" do
    for source <- [
          "builtins.add()",
          "String.upcase(\"host call\")",
          "fn %{lib: renamed} -> renamed end",
          "fn %{lib: %{nested: nested}} -> nested end",
          "fn %{lib: lib, lib: lib} -> lib end"
        ] do
      error = assert_raise CompileError, fn -> quoted!(source) end
      assert error.file == "ergonomics.exs"
      assert error.line == 3
    end
  end

  test "quoted syntax keeps unselected failures symbolic and supports host splicing" do
    {expr, _} =
      Code.eval_string(
        ~S"""
        import NixEx.DSL
        value = 40
        nix do
          if true do
            splice(value) + 2
          else
            throw("forced macro branch")
          end
        end
        """,
        [],
        file: "synthetic.exs"
      )

    assert eval!(expr) == "42"
    assert NixEx.Render.render(expr) =~ "nix-ex source: synthetic.exs:"

    {expr, _} =
      Code.eval_string(~S"""
      import NixEx.DSL
      nix do
        let [f: fn x -> x + 1 end] do
          apply(f, [41])
        end
      end
      """)

    assert eval!(expr) == "42"
  end

  test "unknown syntax fails with original file and line instead of executing Elixir" do
    assert_raise CompileError, ~r/unsupported nix syntax.*System.cmd/s, fn ->
      Code.eval_string("import NixEx.DSL\nnix do: System.cmd(\"touch\", [\"bad\"])", [],
        file: "bad.exs"
      )
    end
  end

  test "source labels are stable and omit absolute machine paths" do
    {expr, _} =
      Code.eval_string("import NixEx.DSL\nnix do: 1 + 2", [], file: "/private/example/source.exs")

    rendered = NixEx.Render.render(expr)
    assert rendered =~ "nix-ex source: source.exs:2"
    refute rendered =~ "/private/example"
  end

  test "unsupported partial forms report CompileError consistently" do
    for source <- ["%{key => 1}", "if true, do: 1", "fn x, y -> x + y end", "let [1], do: 2"] do
      assert_raise CompileError, ~r/unsupported nix syntax/, fn ->
        Code.eval_string("import NixEx.DSL\nnix do\n" <> source <> "\nend", [],
          file: "unsupported.exs"
        )
      end
    end
  end
end
