{
  description = "Elixir constructs Nix syntax; Nix evaluates it";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f13ff45afd1bb73e640eaa08a7066dbed07e3238";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      each = nixpkgs.lib.genAttrs systems;
      make = system:
        let
          pkgs = import nixpkgs { inherit system; };
          elixir = pkgs.beam.packages.erlang_27.elixir_1_18;
          erlang = pkgs.beam27Packages.erlang;
          package = pkgs.stdenvNoCC.mkDerivation {
            pname = "nix-ex";
            version = "0.1.0";
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [ ./mix.exs ./lib ./tests ./test ./examples ./README.md ./docs/MIGRATION.md ];
            };
            strictDeps = true;
            nativeBuildInputs = [ elixir erlang pkgs.makeWrapper ];
            nativeCheckInputs = [ pkgs.nix ];
            ERL_FLAGS = "+S 4:4 +fnu";
            NIX_EX_IN_SHELL = "1";
            NIX_EX_NIXPKGS = toString nixpkgs;
            buildPhase = "mix escript.build";
            postPatch = "patchShebangs test tests/cli/smoke";
            doCheck = true;
            checkPhase = ''
              export NIX_REMOTE="local?root=$TMPDIR/nix-ex-store"
              export NIX_STATE_DIR="$TMPDIR/nix-ex-state"
              export NIX_LOG_DIR="$TMPDIR/nix-ex-log"
              export NIX_CONF_DIR="$TMPDIR/nix-ex-conf"
              export XDG_CACHE_HOME="$TMPDIR/nix-ex-cache"
              export XDG_CONFIG_HOME="$TMPDIR/nix-ex-config"
              export XDG_DATA_HOME="$TMPDIR/nix-ex-data"
              export XDG_STATE_HOME="$TMPDIR/nix-ex-xdg-state"
              export NIX_CONFIG="experimental-features = nix-command flakes
              sandbox = false"
              ./test
            '';
            installPhase = ''
              mkdir -p $out/bin
              cp nix_ex $out/bin/nix-ex
              patchShebangs $out/bin/nix-ex
              wrapProgram $out/bin/nix-ex --prefix PATH : ${pkgs.lib.makeBinPath [ elixir erlang pkgs.nix pkgs.bash ]} --set ERL_FLAGS "+S 4:4 +fnu" --set NIX_EX_NIXPKGS ${nixpkgs}
            '';
          };
        in { inherit pkgs elixir erlang package; };
    in {
      packages = each (system: { default = (make system).package; });
      checks = each (system: { prototype = (make system).package; });
      devShells = each (system: let env = make system; in {
        default = env.pkgs.mkShell {
          packages = [ env.elixir env.erlang env.pkgs.nix ];
          ERL_FLAGS = "+S 4:4 +fnu";
          NIX_EX_IN_SHELL = "1";
          NIX_EX_NIXPKGS = toString nixpkgs;
        };
      });
      apps = each (system: let
        env = make system;
        commandApp = command: {
          type = "app";
          program = toString (env.pkgs.writeShellScript "nix-ex-${command}" ''
            exec ${env.package}/bin/nix-ex ${command} "$@"
          '');
          meta.description = "${command} an Elixir-authored Nix configuration";
        };
      in {
        default = {
          type = "app";
          program = "${env.package}/bin/nix-ex";
          meta.description = "Convert and check Elixir-authored Nix configurations";
        };
        convert = commandApp "convert";
        check = commandApp "check";
        import = commandApp "import";
      });
    };
}
