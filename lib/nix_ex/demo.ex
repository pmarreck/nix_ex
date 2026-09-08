defmodule NixEx.Demo do
  @moduledoc "Synthetic module tree and standalone flake. No host configuration is read."
  alias NixEx.AST, as: N
  alias NixEx.Project, as: P

  def files do
    option = fn type, default ->
      N.call(N.var("lib.mkOption"), [N.attrs(type: type, default: default)])
    end

    options =
      N.fn_(
        N.pattern(["lib"], ellipsis: true),
        N.attrs([
          {["options", "project"],
           N.attrs(
             enable: option.(N.var("lib.types.bool"), false),
             greeting: option.(N.var("lib.types.str"), "disabled"),
             priority: option.(N.var("lib.types.str"), "option default"),
             items: option.(N.call(N.var("lib.types.listOf"), [N.var("lib.types.str")]), [])
           )}
        ])
      )

    service =
      N.fn_(
        N.pattern(["lib", "config", "token"], ellipsis: true),
        N.attrs(
          config:
            N.call(N.var("lib.mkIf"), [
              N.var("config.project.enable"),
              N.attrs([
                {["project", "greeting"],
                 N.call(N.var("lib.mkForce"), [N.string(["hello ", N.var("token")])])},
                {["project", "priority"], N.call(N.var("lib.mkForce"), ["forced"])},
                {["project", "items"], N.call(N.var("lib.mkBefore"), [["first"]])}
              ])
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
              project:
                N.attrs(
                  enable: N.var("enabled"),
                  priority: N.call(N.var("lib.mkDefault"), ["ordinary default"]),
                  items: ["last"]
                )
            )
        )
      )

    expression =
      N.fn_(
        N.pattern(["nixpkgs", {"enabled", true}, {"token", "world"}]),
        N.let(
          [
            lib: N.import_(N.op("+", N.var("nixpkgs"), "/lib")),
            result:
              N.call(N.var("lib.evalModules"), [
                N.attrs(
                  specialArgs: N.attrs([N.inherit_(["token", "enabled"])]),
                  modules: [N.ref("modules/default.nix")]
                )
              ])
          ],
          N.var("result.config.project")
        )
      )

    flake =
      N.attrs(
        description: "Standalone generated nix_ex example",
        outputs:
          N.fn_(
            N.pattern(["self"]),
            N.attrs(
              answer: N.import_(N.ref("expressions/answer"), N.attrs(x: 41)),
              lib: N.attrs(evaluateModules: N.import_(N.ref("default.nix"))),
              nixosModules: N.attrs(default: N.ref("modules/default.nix"))
            )
          )
      )

    [
      P.nix("default.nix", N.at(expression, "demo.ex", 1)),
      P.nix("flake.nix", flake),
      P.nix("modules/default.nix", root_module),
      P.nix("modules/options.nix", options),
      P.nix("modules/service.nix", service),
      P.nix("expressions/answer", N.fn_(N.pattern(["x"]), N.op("+", N.var("x"), 1))),
      P.asset("assets/example.sh", "#!/usr/bin/env bash\nprintf '%s\\n' \"${MESSAGE:-hello}\"\n",
        mode: 0o755
      )
    ]
  end
end
