alias NixEx.AST, as: N
alias NixEx.Project, as: P

# A reusable final: prev: overlay. The final reference sees the overridden answer.
overlay =
  N.fn_(
    "final",
    N.fn_(
      "prev",
      N.attrs(
        answer: N.op("+", N.var("prev.answer"), 1),
        description: N.string(["answer=", N.call(N.var("toString"), [N.var("final.answer")])])
      )
    )
  )

result =
  N.let(
    [
      base: N.attrs(answer: 41),
      final:
        N.op(
          "//",
          N.var("base"),
          N.call(N.import_(N.ref("overlay.nix")), [N.var("final"), N.var("base")])
        )
    ],
    N.var("final")
  )

[P.nix("default.nix", result), P.nix("overlay.nix", overlay)]
