defmodule NixEx.RenderTest do
  use ExUnit.Case, async: true
  alias NixEx.AST, as: N

  test "invalid names, operators, literal values and unknown AST fail clearly" do
    for name <- ["x; abort", "let", "a b", "${bad}"] do
      assert_raise ArgumentError, fn -> N.var(name) end
    end

    assert_raise ArgumentError, fn -> N.op("???", 1, 2) end
    assert_raise ArgumentError, fn -> NixEx.Render.render(self()) end
    assert_raise ArgumentError, fn -> NixEx.Render.render(%NixEx.Expr{op: :unknown, args: []}) end
    assert_raise ArgumentError, fn -> NixEx.Render.render(9_223_372_036_854_775_808) end
    assert_raise ArgumentError, fn -> NixEx.Render.render(<<0>>) end
  end

  test "map input order is deterministic, duplicates are rejected" do
    assert NixEx.Render.render(%{z: 1, a: 2}) == NixEx.Render.render(%{a: 2, z: 1})
    assert_raise ArgumentError, fn -> NixEx.Render.render(N.attrs(a: 1, a: 2)) end
  end
end
