alias NixEx.AST, as: N
alias NixEx.Project, as: P
import NixEx.DSL

# These are NixOS-style modules evaluated with lib.evalModules, without a host.
options =
  nix do
    fn %{lib: lib} ->
      %{
        options: %{
          example: %{
            enabled: lib.mkOption(type: lib.types.bool, default: false),
            message: lib.mkOption(type: lib.types.str, default: "option default"),
            order: lib.mkOption(type: lib.types.listOf(lib.types.str), default: [])
          }
        }
      }
    end
  end

service =
  nix do
    fn %{lib: lib, config: config} ->
      %{
        config:
          lib.mkIf(config.example.enabled, %{
            example: %{
              message: lib.mkForce("welcome"),
              order: lib.mkBefore(["first"])
            }
          })
      }
    end
  end

root_module =
  nix do
    fn %{lib: lib, enabled: enabled} ->
      %{
        imports: [splice(N.ref("modules/options.nix")), splice(N.ref("modules/service.nix"))],
        config: %{
          example: %{
            enabled: enabled,
            message: lib.mkDefault("disabled"),
            order: ["last"]
          }
        }
      }
    end
  end

# Optional Nix function arguments still use the explicit pattern constructor.
entrypoint =
  N.fn_(
    N.pattern(["nixpkgs", {"enabled", true}]),
    nix do
      let lib: builtins.import(nixpkgs + "/lib"),
          result:
            lib.evalModules(
              specialArgs: %{enabled: enabled},
              modules: [splice(N.ref("modules/default.nix"))]
            ) do
        result.config.example
      end
    end
  )

[
  P.nix("default.nix", entrypoint),
  P.nix("modules/default.nix", root_module),
  P.nix("modules/options.nix", options),
  P.nix("modules/service.nix", service)
]
