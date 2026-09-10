# Runnable examples

Each `.exs` file is a complete generator returning a list or finite Stream of
output declarations. Build the CLI once, then generate into a fresh directory:

```sh
./build
./result/bin/nix-ex generate examples/01_macro_and_recursion.exs /tmp/nix-example-01
nix-instantiate --eval --strict --json /tmp/nix-example-01/default.nix
# {"answer":42,"factorial":720}
```

The destination's parent must exist. Changed existing trees are refused;
choose another output directory to compare changes. On macOS use a canonical
path such as `/private/tmp`, since symlink ancestors are refused.

| Generator | Demonstrates | Expected Nix result |
| --- | --- | --- |
| [01_macro_and_recursion.exs](01_macro_and_recursion.exs) | Macro syntax, explicit Elixir splice, unused throwing branch, recursive factorial | `{"answer":42,"factorial":720}` |
| [02_imports_and_assets.exs](02_imports_and_assets.exs) | Extensionless import with arguments, nested source-relative asset, literal shell interpolation | `{"answer":42,"message":"hello ${USER}\n"}` |
| [03_module_merging.exs](03_module_merging.exs) | Typed options, imports, `mkDefault`, `mkForce`, `mkBefore`, config-dependent `mkIf` | `{"enabled":true,"message":"welcome","order":["first","last"]}` |
| [04_overlay.exs](04_overlay.exs) | Reusable `final: prev:` function, recursive overlay fixed point, string interpolation | `{"answer":42,"description":"answer=42"}` |
| [05_stream.exs](05_stream.exs) | Finite Elixir Stream generates three files and a standalone no-input flake | `[10,20,30]` |
| [06_intentional_error.exs](06_intentional_error.exs) | Explicit `N.at` origin annotation and a failure forced by Nix | Nonzero exit: `example intentionally fails` |

For examples 01, 02 and 04, use `nix-instantiate --eval --strict --json` on the
generated `default.nix`. Example 02 reads its input asset with `__DIR__`, so its
generator works from another current directory. The generated tree also works
after relocation; the suite moves it under a directory containing spaces.

Example 03 uses the package's pinned Nixpkgs through `--nixpkgs`:

```sh
nix run .#convert -- examples/03_module_merging.exs /tmp/nix-example-03
nix run .#check -- /tmp/nix-example-03 --nixpkgs --json
nix run .#check -- /tmp/nix-example-03 --nixpkgs --json --arg enabled=false
# Disabled: {"enabled":false,"message":"disabled","order":["last"]}
```

This evaluates synthetic NixOS-style modules through `lib.evalModules`.
It does not instantiate or activate a host configuration. Example 04 evaluates
an overlay against a small synthetic base set and builds no derivations.

Example 03 uses quoted map-pattern lambdas and direct calls such as
`lib.mkOption(type: lib.types.bool, default: false)`. Bare dotted expressions
select Nix attributes; keyword call arguments become Nix attribute sets.
`ref(...)` inserts project paths. Its entrypoint uses `enabled: enabled \\ true`
for the optional argument. Example 01 uses recursive `fact.(n)` calls;
example 04 uses a curried `fn final, prev -> ... end`, a pipe into `Map.merge`,
and ordinary-looking `"answer=#{final.answer}"` interpolation evaluated by Nix.

Example 05 can be consumed as a flake with Nix alone:

```sh
./result/bin/nix-ex generate examples/05_stream.exs /tmp/nix-example-05
nix eval --offline --json path:/tmp/nix-example-05#values
# [10,20,30]
```

The Stream delays finite Elixir generation. Once files exist, Nix handles their
evaluation; it never calls the generator.

## Inspect an intentional runtime error

```sh
./result/bin/nix-ex generate examples/06_intentional_error.exs /tmp/nix-example-06
nix-instantiate --eval --strict --json --show-trace /tmp/nix-example-06/default.nix
```

Generation succeeds and Nix fails. Nix reports a generated `default.nix`
line/column. Inspect the nearby `# nix-ex source: 06_intentional_error.exs:...`
comment to find the original declaration. The example derives its annotation
from `__ENV__.line`; a test checks that it points at the actual `N.at` call.

Unsupported macro syntax raises `CompileError` with the original Elixir file
and line. Nix runtime errors are **not automatically remapped**. Comments retain
basenames, which can be ambiguous, and may not appear in every trace excerpt.
Constructor-only AST nodes require explicit `N.at(...)` annotations. See
[verified error locations](../docs/ERROR_LOCATIONS.md) for actual diagnostics.

`./test` checks all six results, the module's disabled branch, relocation and the
expected failure. CLI checks copy every generator and its asset into a path
containing spaces and run them from another cwd. `./build` runs the same checks
inside the Nix sandbox. No example needs network-dependent package builds.

The built-in `demo` uses the same quoted DSL and is compared against a separate
handwritten Nix module fixture, including changed inputs and a type error.
CLI tests generate it, check it, and detect deliberate output drift. A source
check rejects use of the AST constructor namespace in the demo and ordinary
examples; only example 06 retains it to demonstrate explicit source annotations.
