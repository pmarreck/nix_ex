defmodule NixEx.SemanticsTest do
  use ExUnit.Case, async: true
  alias NixEx.AST, as: N
  import NixEx.TestSupport

  test "Nix chooses branches and leaves unused let bindings and function arguments lazy" do
    boom = N.call(N.var("builtins.throw"), ["forced"])
    assert eval!(N.if_(true, 42, boom)) == "42"
    assert eval!(N.let([unused: boom], 7)) == "7"
    assert eval!(N.call(N.fn_("unused", 9), [boom])) == "9"
    assert eval!(N.op("&&", false, boom)) == "false"
    assert_raise RuntimeError, ~r/forced/, fn -> eval!(N.if_(false, 42, boom)) end
    assert_raise RuntimeError, ~r/forced/, fn -> eval!(N.let([unused: boom], N.var("unused"))) end
    assert eval!(N.let([cycle: N.var("cycle")], 1)) == "1"

    assert_raise RuntimeError, ~r/infinite recursion/, fn ->
      eval!(N.let([cycle: N.var("cycle")], N.var("cycle")))
    end
  end

  test "full signed integer range survives Nix parsing" do
    assert eval!(-9_223_372_036_854_775_808) == "-9223372036854775808"
    assert eval!(9_223_372_036_854_775_807) == "9223372036854775807"
  end

  test "recursive bindings and recursive functions retain Nix scope" do
    assert eval!(N.select(N.attrs([a: N.var("b"), b: 12], recursive: true), ["a"])) == "12"

    factorial =
      N.fn_(
        "n",
        N.if_(
          N.op("==", N.var("n"), 0),
          1,
          N.op("*", N.var("n"), N.call(N.var("fact"), [N.op("-", N.var("n"), 1)]))
        )
      )

    assert eval!(N.let([fact: factorial], N.call(N.var("fact"), [6]))) == "720"
  end

  test "strings preserve shell interpolation, quotes, slashes and newlines" do
    value = "shell ${HOME} \\\"\n\tλ"
    assert eval!(value) == ~s("shell ${HOME} \\\\\\\"\\n\\tλ")
    assert eval!(N.string(["hello ", N.var("builtins.nixVersion")])) =~ "hello "
  end

  test "patterns, dynamic attributes, inherit, with, defaults and operators" do
    pattern = N.pattern([{"x", 3}], ellipsis: true, at: "args")
    body = N.op("+", N.var("x"), N.select(N.var("args"), ["y"], 4))
    assert eval!(N.call(N.fn_(pattern, body), [N.attrs(y: 5)])) == "8"
    assert eval!(N.select(N.attrs([{[N.dynamic("a b")], 8}]), ["a b"])) == "8"
    assert eval!(N.let([x: 5], N.attrs([N.inherit_(["x"])]))) == ~s({"x":5})
    assert eval!(N.with_(N.attrs(a: 6), N.var("a"))) == "6"
    assert eval!(N.has(N.attrs(a: 1), ["a"])) == "true"
    assert eval!(N.assert_(true, N.op("++", [1], [2]))) == "[1,2]"
  end

  test "overlays are curried Nix functions and lexical shadowing stays in Nix" do
    overlay =
      N.fn_(
        "final",
        N.fn_(
          "prev",
          N.attrs(
            answer: N.op("+", N.var("prev.answer"), 1),
            forward: N.var("final.answer")
          )
        )
      )

    result = N.call(overlay, [N.attrs(answer: 42), N.attrs(answer: 41)])
    assert eval!(result) == ~s({"answer":42,"forward":42})
    assert eval!(N.let([x: 1], N.let([x: 2], N.var("x")))) == "2"
    assert eval!(N.attrs([N.inherit_(N.attrs(x: 3), ["x"])])) == ~s({"x":3})

    assert_raise RuntimeError, ~r/required argument/, fn ->
      eval!(N.call(N.fn_(N.pattern(["x"]), N.var("x")), [N.attrs([])]))
    end
  end

  test "operator families retain their target semantics" do
    cases = [
      {N.op("//", N.attrs(x: 1), N.attrs(x: 2)), ~s({"x":2})},
      {N.op("/", 9, 2), "4"},
      {N.op("/", 9.0, 2), "4.5"},
      {N.op("->", false, false), "true"},
      {N.unary("!", true), "false"},
      {N.unary("-", 3), "-3"},
      {N.op("!=", 1, 2), "true"},
      {N.op("<", 1, 2), "true"},
      {N.op(">", 2, 1), "true"},
      {N.op("<=", 1, 1), "true"},
      {N.op(">=", 1, 1), "true"},
      {N.op("||", false, true), "true"},
      {nil, "null"}
    ]

    for {expression, expected} <- cases, do: assert(eval!(expression) == expected)
  end
end
