alias NixEx.AST, as: N
alias NixEx.Project, as: P

# __DIR__ makes reading a generator asset independent of the CLI's cwd.
message = File.read!(Path.join(__DIR__, "assets/message.txt"))

result =
  N.fn_(
    N.pattern(["x"]),
    N.attrs(
      answer: N.op("+", N.var("x"), 1),
      message: N.call(N.var("builtins.readFile"), [N.source_path("../assets/message.txt")])
    )
  )

[
  P.nix("default.nix", N.import_(N.ref("modules/result"), N.attrs(x: 41))),
  P.nix("modules/result", result),
  P.asset("assets/message.txt", message)
]
