# Thelio configuration requirements

Observed 2026-09-08 EDT by Einstein. Read-only source inventory, not a completed
translation or an evaluated dependency graph.

Baseline: `/etc/nixos`, Git commit
`c93d8d291376c8a6337010ebda6b3412de308a4a`. The worktree had an unrelated modified
`PLAN.md`; it was not changed by this investigation. The installed evaluator
reported Nix 2.34.8. Host-global Elixir was 1.14.5 on OTP 25, which is not a
reason to pin the new project's development toolchain to that old installation.

The top-level flake is 211 lines and the main Thelio module is 2,034 lines.
Line counts indicate scope only, not coverage or complexity scores. Comments,
unused bindings and unselected package definitions must not be mistaken for
evaluated dependencies by a text scan.

## Entry and module graph

The flake defines `nixosConfigurations.thelio-nixos` with `lib.nixosSystem`.
Its `specialArgs` inject flake inputs, target system and selected packages into
the main module. The main module explicitly accepts named arguments and `...`.

Local imports cover hardware, ZFS, UPS monitoring, Ollama, binary caching, CI
receiver/worker/operations, keyboard accents and rotational-I/O settings. The
mail module comes from an external flake's `nixosModules.default` output.
Three local CI module files forward to another file with a plain Nix `import`.

The generated tree therefore needs to preserve these distinct relationships:

| Source pattern | Required meaning |
| --- | --- |
| `import ./expression.nix` | Evaluate a Nix expression in another file |
| `import ./expression.nix { inherit pkgs; }` | Apply the imported function |
| `imports = [ ./module.nix ];` | Contribute a module to NixOS option evaluation |
| `inputs.service.nixosModules.default` | Use an external flake module without embedding it |
| `import ./packages` | Resolve the directory's `default.nix` |
| `pkgs.callPackage ./packages/accentd { }` | Load an extensionless Nix file and inject package arguments |
| `../nix/packages.nix` | Resolve relative to the referencing generated file |
| `builtins.readFile ../scripts/worker.bash` | Read a declared non-Nix asset at evaluation time |
| `${./ups/monitor.lua}` | Keep a Nix path expression inside interpolation |

The extensionless package files are regular files, not directories. A collector
that assumes all expression files end in `.nix` would miss real inputs.

## Expression and module capabilities exercised

- Attribute-set function patterns, ellipses, whole-argument bindings in flake
  outputs, simple and curried functions for overlays and package overrides.
- Recursive `let` bindings, `rec` attribute sets, `inherit`, `with`, conditionals,
  assertions, attribute selection, dynamic attributes and ordinary operators.
- Multiple pinned Nixpkgs scopes with separate package configuration. Do not
  collapse stable/unstable scopes or silently change their input pins.
- `lib.mkOption`, types, defaults, `lib.mkDefault`, `lib.mkForce`, `lib.mkBefore`,
  and references to other `config` values. NixOS option merging belongs to
  Nixpkgs, not an Elixir map-merge operation.
- `pkgs.callPackage`, `override`, `overrideAttrs`, fetchers, `runCommand`,
  `writeShellApplication` and `writeShellScriptBin`. These are ordinary Nix
  function applications, not a finite list of special cases for the DSL.
- Plain and indented strings containing Nix interpolation, shell variables,
  nested quotes, backslashes, JSON, Lua and regular expressions.
- File and directory assets, `builtins.path` with an explicit stable name,
  `toString` of paths, plus inputs that are raw downloaded files rather than flakes.

The Firefox overlay also contains version discovery and fetch expressions
inside lazy package definitions. Rendering these expressions must not trigger
their network access in Elixir. Whether Nix subsequently forces them depends on
the selected evaluation target. Do not modernize or repair the source during a
translation experiment; that would confound the comparison.

## Multi-file generation contract

1. Model a project as explicit output identities and their contents, not a set
   of snippets blindly concatenated into one file.
2. Keep Nix expression imports separate from Elixir code organization. An
   Elixir module can generate several Nix files; a Nix file can combine values
   assembled by multiple Elixir modules.
3. Resolve file references relative to each generated file, independent of
   the shell's current directory. Generated trees should survive relocation.
4. Make copies of required assets explicit. Preserve necessary executable bits
   and consider symlink behavior before accepting arbitrary asset trees.
5. Validate the entire output plan before writing it: duplicate destinations,
   files overlapping directories, traversal, symlink escapes and overwrites of
   user-owned files require explicit handling. A malformed late entry must not
   leave earlier files looking like a complete successful generation.
6. No Elixir/Mix execution during ordinary consumption of the generated flake.
   Produce `flake.nix` before Nix needs to resolve its inputs; avoid a circular
   generator dependency or import-from-derivation bootstrap.
7. Regeneration must be deterministic. Input ordering, host usernames, cwd,
   filesystem traversal order, environment variables and clock reads must not
   silently influence the output.

## Important limits to exact equivalence

Generated source paths, source positions, and flake source contents can be
observable in Nix. Even an equivalent module may yield different derivation
paths if a build embeds the whole source tree or references a renamed asset.
Functions such as source-position introspection make universal observational
identity stronger than merely expressing all language constructs.

The target is faithful configuration behavior with an explicit accounting of
path-sensitive differences. Never strip every store hash or suppress differing
options to manufacture an equality result.

## Privacy and operational boundary

Use synthetic hostnames, users, keys, disks, endpoints and addresses in committed
fixtures. Keep real comparison inputs in their existing private location.
No generated deployment may replace `/etc/nixos`, alter storage or networking,
or activate system/user services without a separate explicit migration request.

Full Thelio migration is a future acceptance stage. A passing small module demo
is evidence for feasibility, not evidence that the whole host has been ported.
