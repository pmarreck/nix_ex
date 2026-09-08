alias NixEx.AST, as: N
alias NixEx.Project, as: P

# These are NixOS-style modules evaluated with lib.evalModules, without a host.
option = fn type, default ->
  N.call(N.var("lib.mkOption"), [N.attrs(type: type, default: default)])
end

options =
  N.fn_(
    N.pattern(["lib"], ellipsis: true),
    N.attrs(
      options:
        N.attrs(
          example:
            N.attrs(
              enabled: option.(N.var("lib.types.bool"), false),
              message: option.(N.var("lib.types.str"), "option default"),
              order: option.(N.call(N.var("lib.types.listOf"), [N.var("lib.types.str")]), [])
            )
        )
    )
  )

service =
  N.fn_(
    N.pattern(["lib", "config"], ellipsis: true),
    N.attrs(
      config:
        N.call(N.var("lib.mkIf"), [
          N.var("config.example.enabled"),
          N.attrs(
            example:
              N.attrs(
                message: N.call(N.var("lib.mkForce"), ["welcome"]),
                order: N.call(N.var("lib.mkBefore"), [["first"]])
              )
          )
        ])
    )
  )

root_module =
  N.fn_(
    N.pattern(["lib", "enabled"], ellipsis: true),
    N.attrs(
      imports: [N.ref("modules/options.nix"), N.ref("modules/service.nix")],
      config:
        N.attrs(
          example:
            N.attrs(
              enabled: N.var("enabled"),
              message: N.call(N.var("lib.mkDefault"), ["disabled"]),
              order: ["last"]
            )
        )
    )
  )

entrypoint =
  N.fn_(
    N.pattern(["nixpkgs", {"enabled", true}]),
    N.let(
      [
        lib: N.import_(N.op("+", N.var("nixpkgs"), "/lib")),
        result:
          N.call(N.var("lib.evalModules"), [
            N.attrs(
              specialArgs: N.attrs([N.inherit_(["enabled"])]),
              modules: [N.ref("modules/default.nix")]
            )
          ])
      ],
      N.var("result.config.example")
    )
  )

[
  P.nix("default.nix", entrypoint),
  P.nix("modules/default.nix", root_module),
  P.nix("modules/options.nix", options),
  P.nix("modules/service.nix", service)
]
