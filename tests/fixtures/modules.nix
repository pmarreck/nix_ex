{ nixpkgs, enabled ? true, token ? "world" }:
let
  lib = import (nixpkgs + "/lib");
  result = lib.evalModules {
    specialArgs = { inherit token; };
    modules = [
      ({ lib, ... }: {
        options.project = {
          enable = lib.mkOption { type = lib.types.bool; default = false; };
          greeting = lib.mkOption { type = lib.types.str; default = "disabled"; };
          priority = lib.mkOption { type = lib.types.str; default = "option default"; };
          items = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
        };
      })
      ({ lib, ... }: {
        config.project = {
          enable = enabled;
          priority = lib.mkDefault "ordinary default";
          items = [ "last" ];
        };
      })
      ({ lib, config, token, ... }: {
        config = lib.mkIf config.project.enable {
          project.greeting = lib.mkForce "hello ${token}";
          project.priority = lib.mkForce "forced";
          project.items = lib.mkBefore [ "first" ];
        };
      })
    ];
  };
in result.config.project
