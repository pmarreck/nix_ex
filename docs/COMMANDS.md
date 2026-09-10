# Convert and check

Build with `./build`, then run `./result/bin/nix-ex`. Installing the package puts
`nix-ex` on your PATH. Alternatively, register `ex` once:

```sh
nix registry add ex github:pmarreck/nix_ex
```

The Nix app forms work from any project directory:

| Task | Installed command | Nix app |
| --- | --- | --- |
| Generate Nix | `nix-ex convert` | `nix run ex#convert` |
| Check generated Nix | `nix-ex check` | `nix run ex#check` |
| Import an existing expression | `nix-ex import module.nix` | `nix run ex#import -- module.nix` |

In the nix_ex checkout, `nix run .#convert` and `nix run .#check` need no registry
entry. `--help` is available for every command app.

## Defaults and settings

`convert` reads `generate.exs` and writes `generated/` beside it. The script can
return one expression, a nonempty list of `Project.nix/asset` entries, or a finite
Stream of entries. Standalone list expressions, including `[]`, become
`generated/default.nix`. The explicit `generate SCRIPT DESTINATION` command
remains available for arbitrary project enumerables, including empty projects.

Override the input or output when needed:

```sh
nix-ex convert config.exs
nix-ex convert generate.exs next-generation
```

Changed destinations are refused; byte-identical regeneration succeeds. Use a
fresh output directory for an edited configuration. `import module.nix` writes
`module.nix.exs` beside it and also refuses to overwrite edited files or symlinks.
It imports one expression; declare its referenced files and assets when assembling
a complete project. See the [migration guide](MIGRATION.md).

Save recurring settings as `nix-ex.exs` in your configuration directory:

```elixir
[
  source: "generate.exs",
  output: "generated",
  attribute: "nixosConfigurations.workstation.config.system.build.toplevel.drvPath",
  offline: true
]
```

Now both commands need no arguments. `--project /path/to/nix-ex.exs` selects a
settings file from another directory. Paths in settings resolve relative to
that file; command-line paths resolve relative to the working directory.
`--attr` overrides `attribute`. Optional `inputs: [name: "flake-reference"]`
settings supply flake input overrides to Nix. Use complete URI references there.
Elixir generators and settings are trusted programs with ordinary host access.

## What checking proves

- A Nix expression or directory with `default.nix` is evaluated with `--strict`.
  Unapplied functions remain functions; their bodies require arguments to test.
- A flake with an attribute selected by `--attr` or project settings evaluates
  that attribute as JSON. Selecting a NixOS system's `drvPath` forces system
  derivation evaluation without building it.
- A flake without an attribute runs `nix flake check --no-build`. That checks
  recognized flake outputs, rather than evaluating every arbitrary output.
- `--against ORIGINAL` compares decoded JSON values from both expressions.
  Flake comparisons require an attribute. Unequal results or either evaluation
  failing returns a nonzero exit status. Store paths compare exactly; relocation
  differences must be investigated rather than silently normalized.

```sh
nix-ex check generated
nix-ex check generated --attr answer
nix-ex check generated --against original.nix
nix-ex check module-nix --nixpkgs --json
nix-ex check module-nix --nixpkgs --json --arg enabled=false
```

For expression files, `--nixpkgs` applies the package's pinned Nixpkgs path as
the `nixpkgs` function argument. `--arg NAME=EXPRESSION` supplies other arguments
and can be repeated; values are Nix expressions, so quote strings as Nix strings.
Arguments are passed directly to Nix without shell evaluation. These application
flags do not apply to flakes. Checks without arguments leave functions unapplied.

`--json` prints the evaluated value instead of a success message. Flakes require
an attribute for JSON output. Use `--against` separately to report equality.

Checks disable import-from-derivation and do not write lock files. Flake input
fetching remains possible unless `--offline` or the project setting disables it.
Diagnostics are captured separately from JSON values, so Nix traces and warnings
cannot corrupt comparisons. Failures include Nix's diagnostic text.

Checking a generated tree does not check whether it is current with respect to
edited Elixir. Convert the current source into a fresh tree before comparing it.
The tests include changed values, forced errors, strict argument failures,
literal paths with spaces, protected destinations and refusal to execute IFD.
