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

  test "binding blocks preserve inheritance, recursive attributes and outer scope" do
    assert eval!(quoted!("let x: 7 do attrs do x = 1; y = x end end")) == ~s({"x":1,"y":7})
    assert eval!(quoted!("let x: 7 do rec do x = 1; y = x end end")) == ~s({"x":1,"y":1})
    assert eval!(quoted!("let do y = x + 1; x = 41; y end")) == "42"

    assert eval!(
             quoted!(~S"""
             let x: 7 do
               let do
                 inherit(x)
                 next = x + 1
                 rec do
                   inherit(x, next)
                   %{answer: next + 1}
                 end
               end
             end
             """)
           ) == ~s({"answer":9,"next":8,"x":7})

    assert eval!(
             quoted!(~S"""
             attrs do
               inherit(%{answer: 42}, [:answer])
               %{other: 3}
             end
             """)
           ) == ~s({"answer":42,"other":3})
  end

  test "whole-argument bindings preserve lazy defaults and exact patterns reject extra keys" do
    assert eval!(
             quoted!(~S"""
             (fn args = exact(%{x: x \\ 3}) -> %{x: x, supplied: has?(args, ["x"])} end).(%{})
             """)
           ) == ~s({"supplied":false,"x":3})

    assert_raise RuntimeError, ~r/unexpected argument/, fn ->
      eval!(quoted!("(fn exact(%{x: x}) -> x end).(%{x: 1, extra: 2})"))
    end
  end

  test "dynamic keys and selection defaults remain lazy" do
    assert eval!(
             quoted!(~S"""
             let key: "answer" do
               get(%{key => 42}, [key], throw("unused"))
             end
             """)
           ) == "42"

    assert eval!(quoted!(~S|get(%{}, ["missing"], 42)|)) == "42"
  end

  test "Nix string sigils retain interpolation coercion and literal escaping" do
    assert eval!(quoted!(~S|let x: "world" do ~n"hello #{x}\n\#{literal}" end|)) ==
             ~s("hello world\\n\#{literal}")

    assert_raise RuntimeError, ~r/coerce.*Boolean|coerce.*boolean/, fn ->
      eval!(quoted!(~S|~n"#{true}"|))
    end
  end

  test "explicit Nix scope helpers preserve with lookup and assertions" do
    assert eval!(
             quoted!(~S"""
             with_nix %{answer: 42} do
               assert_nix answer == 42 do
                 answer
               end
             end
             """)
           ) == "42"

    assert_raise RuntimeError, ~r/assertion/, fn ->
      eval!(quoted!("assert_nix false do 42 end"))
    end

    assert eval!(quoted!(~S|let ["custom-name": 42] do var("custom-name") end|)) == "42"
  end

  test "optional map arguments use lazy Nix defaults and preserve false and null overrides" do
    alias NixEx.AST, as: N

    module =
      quoted!(~S"""
      fn %{base: base, answer: answer \\ (base + 2), enabled: enabled \\ true} ->
        %{answer: answer, enabled: enabled}
      end
      """)

    assert eval!(N.call(module, [N.attrs(base: 40)])) == ~s({"answer":42,"enabled":true})
    assert eval!(N.call(module, [N.attrs(base: 10)])) == ~s({"answer":12,"enabled":true})

    assert eval!(N.call(module, [N.attrs(base: 40, answer: nil, enabled: false)])) ==
             ~s({"answer":null,"enabled":false})

    dangerous =
      quoted!(~S"""
      fn %{value: value \\ builtins.throw("default forced")} -> value end
      """)

    assert eval!(N.call(dangerous, [N.attrs(value: 7)])) == "7"

    assert_raise RuntimeError, ~r/default forced/, fn ->
      eval!(N.call(dangerous, [N.attrs([])]))
    end

    unused =
      quoted!(~S"""
      fn %{value: value \\ builtins.throw("unused default")} -> 42 end
      """)

    assert eval!(N.call(unused, [N.attrs([])])) == "42"
  end

  test "optional map patterns reject renamed variables and duplicate keys" do
    for source <- [
          ~S|fn %{value: renamed \\ 1} -> renamed end|,
          ~S|fn %{value: value, value: value \\ 1} -> value end|
        ] do
      assert_raise CompileError, fn -> quoted!(source) end
    end
  end

  test "anonymous calls support recursive functions and curried multi-argument lambdas" do
    assert eval!(
             quoted!(~S"""
             let [subtract: fn x, y -> x - y end, from_fifty: subtract.(50)] do
               %{direct: subtract.(50, 8), partial: from_fifty.(9)}
             end
             """)
           ) == ~s({"direct":42,"partial":41})

    assert eval!(
             quoted!(~S"""
             let [fact: fn n -> if n == 0, do: 1, else: n * fact.(n - 1) end] do
               fact.(6)
             end
             """)
           ) == "720"

    assert eval!(
             quoted!(~S"""
             (fn %{base: base}, %{delta: delta \\ 2} -> base + delta end).(%{base: 40}, %{})
             """)
           ) == "42"
  end

  test "anonymous call keywords and unused arguments retain Nix semantics" do
    assert eval!(
             quoted!(~S"""
             (fn %{answer: answer} -> answer end).(answer: 42)
             """)
           ) == "42"

    assert eval!(
             quoted!(~S"""
             (fn unused -> 42 end).(builtins.throw("anonymous forced"))
             """)
           ) == "42"

    assert_raise RuntimeError, ~r/anonymous forced/, fn ->
      eval!(quoted!(~S|(fn x -> x end).(builtins.throw("anonymous forced"))|))
    end
  end

  test "pipes insert the first argument in order for dotted and anonymous calls" do
    assert eval!(
             quoted!(~S"""
             let [subtract: fn x, y -> x - y end] do
               50 |> subtract.(6) |> builtins.sub(2)
             end
             """)
           ) == "42"

    assert eval!(quoted!(~S'"answer" |> builtins.getAttr(answer: 42)')) == "42"
  end

  test "invalid call and function shapes retain compile errors" do
    for source <- [
          "(fn x -> x end).()",
          "fn -> 42 end",
          "fn x, x -> x end",
          "fn %{x: x}, x -> x end",
          "fn x when x > 0 -> x end",
          "fn 0 -> 1; x -> x end",
          "42 |> 7",
          ~S'"host" |> String.upcase()'
        ] do
      assert_raise CompileError, fn -> quoted!(source) end
    end
  end

  test "path helpers and imports preserve assets and argument application after relocation" do
    alias NixEx.Project, as: P
    root = tmp!()
    destination = Path.join(root, "generated")
    entry = quoted!(~S|import_nix(ref("nested/module"), x: 41)|)

    nested =
      quoted!(~S"""
      fn %{x: x} ->
        %{answer: x + 1, message: builtins.readFile(source_path("../assets/message.txt"))}
      end
      """)

    P.write(
      [
        P.nix("default.nix", entry),
        P.nix("nested/module", nested),
        P.asset("assets/message.txt", "hello ${USER}\n")
      ],
      destination
    )

    relocated = Path.join(root, "moved tree")
    File.rename!(destination, relocated)

    assert {~s({"answer":42,"message":"hello ${USER}\\n"}), 0} ==
             eval_file(Path.join(relocated, "default.nix"))

    File.write!(Path.join(relocated, "assets/message.txt"), "changed")

    assert {~s({"answer":42,"message":"changed"}), 0} ==
             eval_file(Path.join(relocated, "default.nix"))

    assert_raise ArgumentError, fn ->
      P.write([P.nix("default.nix", quoted!(~S|ref("../escape")|))], Path.join(root, "bad"))
    end

    refute File.exists?(Path.join(root, "bad"))
  end

  test "interpolation converts Nix values while preserving shell expansion and literal text" do
    expression =
      quoted!(~S"""
      let [answer: 42] do
        "λ ${HOME}: #{answer}\n#{builtins.add(1, 2)} \\\""
      end
      """)

    assert eval!(expression) == eval!("λ ${HOME}: 42\n3 \\\"")
    assert eval!(quoted!(~S|["#{true}", "#{false}", "#{nil}"]|)) == ~s(["1","",""])

    assert eval!(
             quoted!(~S|if true, do: "ok", else: "#{builtins.throw("interpolation forced")}"|)
           ) == ~s("ok")

    assert_raise RuntimeError, ~r/interpolation forced/, fn ->
      eval!(quoted!(~S|"#{builtins.throw("interpolation forced")}"|))
    end

    assert_raise CompileError, fn -> quoted!(~S|"#{System.get_env("HOME")}"|) end
    assert_raise CompileError, fn -> quoted!("<<1, 2>>") end
  end

  test "Map.merge is a shallow right-biased Nix update and supports overlay recursion" do
    assert eval!(quoted!("%{answer: 41} |> Map.merge(answer: 42)")) == ~s({"answer":42})

    assert eval!(
             quoted!(~S"""
             Map.merge(%{nested: %{a: 1}, kept: true}, %{nested: %{b: 2}, added: 3})
             """)
           ) == ~s({"added":3,"kept":true,"nested":{"b":2}})

    assert eval!(
             quoted!(~S"""
             let [
               overlay: fn final, prev -> %{answer: prev.answer + 1, forward: final.answer} end,
               base: %{answer: 41}, final: base |> Map.merge(overlay.(final, base))
             ] do
               final
             end
             """)
           ) == ~s({"answer":42,"forward":42})

    assert eval!(quoted!(~S|Map.merge(%{x: builtins.throw("replaced")}, %{x: 42}).x|)) == "42"
    assert_raise CompileError, fn -> quoted!("Map.merge(%{}, %{}, fn x -> x end)") end
    assert_raise CompileError, fn -> quoted!("Map.delete(%{}, :x)") end
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
    for source <- ["if true, do: 1", "let [1], do: 2"] do
      assert_raise CompileError, ~r/unsupported nix syntax/, fn ->
        Code.eval_string("import NixEx.DSL\nnix do\n" <> source <> "\nend", [],
          file: "unsupported.exs"
        )
      end
    end
  end
end
