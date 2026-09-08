defmodule NixEx.Demo do
  @moduledoc "Synthetic module tree and standalone flake. No host configuration is read."
  import NixEx.DSL
  alias NixEx.Project, as: P

  def files do
    options =
      nix do
        fn %{lib: lib} ->
          %{
            options: %{
              project: %{
                enable: lib.mkOption(type: lib.types.bool, default: false),
                greeting: lib.mkOption(type: lib.types.str, default: "disabled"),
                priority: lib.mkOption(type: lib.types.str, default: "option default"),
                items: lib.mkOption(type: lib.types.listOf(lib.types.str), default: [])
              }
            }
          }
        end
      end

    service =
      nix do
        fn %{lib: lib, config: config, token: token} ->
          %{
            config:
              lib.mkIf(config.project.enable, %{
                project: %{
                  greeting: lib.mkForce("hello #{token}"),
                  priority: lib.mkForce("forced"),
                  items: lib.mkBefore(["first"])
                }
              })
          }
        end
      end

    root_module =
      nix do
        fn %{lib: lib, enabled: enabled} ->
          %{
            imports: [ref("modules/options.nix"), ref("modules/service.nix")],
            config: %{
              project: %{
                enable: enabled,
                priority: lib.mkDefault("ordinary default"),
                items: ["last"]
              }
            }
          }
        end
      end

    expression =
      nix do
        fn %{nixpkgs: nixpkgs, enabled: enabled \\ true, token: token \\ "world"} ->
          let lib: builtins.import(nixpkgs + "/lib"),
              result:
                lib.evalModules(
                  specialArgs: %{token: token, enabled: enabled},
                  modules: [ref("modules/default.nix")]
                ) do
            result.config.project
          end
        end
      end

    flake =
      nix do
        %{
          description: "Standalone generated nix_ex example",
          outputs: fn %{self: self} ->
            %{
              answer: import_nix(ref("expressions/answer"), x: 41),
              lib: %{evaluateModules: import_nix(ref("default.nix"))},
              nixosModules: %{default: ref("modules/default.nix")}
            }
          end
        }
      end

    answer = nix(do: fn %{x: x} -> x + 1 end)

    [
      P.nix("default.nix", expression),
      P.nix("flake.nix", flake),
      P.nix("modules/default.nix", root_module),
      P.nix("modules/options.nix", options),
      P.nix("modules/service.nix", service),
      P.nix("expressions/answer", answer),
      P.asset("assets/example.sh", "#!/usr/bin/env bash\nprintf '%s\\n' \"${MESSAGE:-hello}\"\n",
        mode: 0o755
      )
    ]
  end
end
