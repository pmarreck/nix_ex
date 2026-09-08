defmodule NixEx.DSLTest do
  use ExUnit.Case, async: true
  import NixEx.TestSupport

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
        Code.eval_string("import NixEx.DSL\nnix do\n" <> source <> "\nend", [], file: "unsupported.exs")
      end
    end
  end
end
