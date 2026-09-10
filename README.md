# nix_ex

[![Mechatron Prime CI](https://img.shields.io/endpoint?url=https%3A%2F%2Fthelio-nixos.tail66c90.ts.net%2Fbadges%2Fnix_ex.json&style=for-the-badge)](https://thelio-nixos.tail66c90.ts.net/mechatron-prime/)

Write Nix configurations in familiar Elixir syntax. Generate ordinary,
relocatable Nix files that work with Nix alone.

`nix_ex` is an experimental authoring layer for Elixir developers who find Nix
hard to approach. Inside `nix do`, a macro turns your expressions into Nix
syntax. Nix handles lazy evaluation, recursive bindings, and module merging.
Outside the block, you have ordinary Elixir for organizing and generating files.

[Project intent](INTENT.md) · [DSL guide](docs/PROTOTYPE.md) · [Examples](examples/README.md) · [Current work](PLAN.md)

## Short commands

Register the flake once, then use its command apps from your configuration directory:

```sh
nix registry add ex github:pmarreck/nix_ex
nix run ex#convert
nix run ex#check
```

`convert` reads `generate.exs` and writes `generated/`. `check` evaluates the
result without building or activating a system. Put long output attributes and
input overrides in `nix-ex.exs`, so these everyday commands stay short.

For individual files or comparisons:

```sh
nix run ex#import -- module.nix
nix run ex#convert -- module.nix.exs
nix run ex#check -- generated --against original.nix
```

An installed package offers the same commands as `nix-ex import`, `nix-ex convert`
and `nix-ex check`. In this checkout, use `nix run .#convert` or the built
`./result/bin/nix-ex`. See [command settings and checking limits](docs/COMMANDS.md).

These are ordinary Nix flake apps. Native `nix ex` subcommands would require a
compiled plugin matched to Nix's unstable plugin API; flake apps avoid that
dependency. [Nix plugin documentation](https://nix.dev/manual/nix/2.34/command-ref/conf-file.html#conf-plugin-files)

## Quick start

Install Nix with flakes and `nix-command` enabled. The project supplies its pinned
Elixir/OTP toolchain through Nix; a separate Elixir installation is unnecessary.

```sh
git clone https://github.com/pmarreck/nix_ex.git
cd nix_ex
./build
```

Save this complete generator as `hello.exs`:

<!-- example: quickstart -->
```elixir
import NixEx.DSL
alias NixEx.Project, as: P

expression =
  nix do
    let name: "Elixir", double: fn x -> x * 2 end do
      %{answer: double.(21), greeting: "hello #{name}"}
    end
  end

[P.nix("default.nix", expression)]
```

Generate the Nix files, then evaluate them:

```sh
./result/bin/nix-ex generate hello.exs ./hello-nix
nix-instantiate --eval --strict --json ./hello-nix/default.nix
```

```json
{"answer":42,"greeting":"hello Elixir"}
```

You can move `hello-nix` elsewhere and evaluate it without Elixir. Use a fresh
destination with an existing parent. Identical output is a successful no-op;
changed existing trees are refused, so generate into another directory to
compare revisions. Symlink ancestors are refused too; on macOS use canonical
paths such as `/private/tmp` instead of `/tmp`.

Generator scripts are trusted Elixir programs with ordinary host access. Only
run generators you trust.

## Declare module options

Write calls such as `lib.mkOption(...)` directly. There is no need to construct
function-call or attribute-set AST nodes yourself:

<!-- example: options -->
```elixir
import NixEx.DSL

nix do
  fn %{lib: lib} ->
    %{
      options: %{
        example: %{
          enabled: lib.mkOption(type: lib.types.bool, default: false),
          message: lib.mkOption(type: lib.types.str, default: "welcome")
        }
      }
    }
  end
end
```

This expression produces a Nix module function. Nixpkgs supplies `lib` when it
evaluates the module; `lib` is not an Elixir variable or a universal Nix import.
Map-pattern arguments allow additional keys, corresponding to `{ lib, ... }:`.

The complete [module-merging generator](examples/03_module_merging.exs) adds
imports, list ordering, `mkDefault`, `mkForce`, and conditional configuration.
Run it with the project's pinned Nixpkgs:

```sh
./result/bin/nix-ex generate examples/03_module_merging.exs ./module-nix
nix develop -c bash -c 'nix-instantiate --eval --strict --json ./module-nix/default.nix --arg nixpkgs "$NIX_EX_NIXPKGS"'
```

```json
{"enabled":true,"message":"welcome","order":["first","last"]}
```

Add `--arg enabled false` inside that quoted command to evaluate the disabled
branch. It returns `{"enabled":false,"message":"disabled","order":["last"]}`.
This runs synthetic modules through `lib.evalModules`; it does not activate a host.

## Write an overlay

Multi-argument lambdas become curried Nix functions. Interpolation stays in Nix:

<!-- example: overlay -->
```elixir
import NixEx.DSL

nix do
  fn final, prev ->
    %{answer: prev.answer + 1, description: "answer=#{final.answer}"}
  end
end
```

The [complete overlay example](examples/04_overlay.exs) uses
`base |> Map.merge(import_nix(ref("overlay.nix")).(final, base))` to evaluate
its recursive fixed point.

```sh
./result/bin/nix-ex generate examples/04_overlay.exs ./overlay-nix
nix-instantiate --eval --strict --json ./overlay-nix/default.nix
```

```json
{"answer":42,"description":"answer=42"}
```

## Syntax at a glance

Advanced forms also stay in the DSL. A whole-argument binding uses Elixir's `=`;
`exact(...)` explicitly rejects extra keys, and `inherit` retains Nix scope:

<!-- example: advanced -->
```elixir
import NixEx.DSL

nix do
  fn options = exact(%{name: name \\ "Elixir"}) ->
    attrs do
      inherit(name)
      supplied = has?(options, ["name"])
      message = ~n"""
      Hello, #{name}!
      Shell ${HOME} stays literal.
      """
    end
  end
end
```

`~n` uses Nix interpolation directly, including path copying and string context.
Ordinary `"#{value}"` retains the DSL's explicit `builtins.toString` conversion.

All forms below belong inside `nix do ... end`.

| Elixir form | Generated Nix meaning |
| --- | --- |
| `lib.types.bool` | Select an attribute; bare function attributes remain values |
| `lib.mkOption(type: lib.types.bool, default: false)` | Apply a function to an attribute set |
| `f.(x, y)` | Curried application, `f x y` |
| `x \|> f.(y)` | Insert `x` as the first argument |
| `fn %{enabled: enabled \\ true} -> enabled end` | Attribute-set function with a lazy default |
| `Map.merge(left, right)` | Shallow, right-biased `left // right` |
| `ref("modules/service.nix")` | Path to a declared project output |
| `source_path("../assets/message.txt")` | Path relative to the generated file |
| `import_nix(ref("value.nix"), x: 41)` | Import and apply an expression |
| `splice(host_value)` | Insert a value computed by ordinary Elixir |
| `with_nix pkgs do [git, curl] end` | Evaluate the body with Nix's `with pkgs;` scope |
| `assert_nix enabled do value end` | Keep a Nix assertion lazy until its result is demanded |
| `var("custom-name")` | Refer to a Nix identifier that Elixir cannot spell directly |
| `attrs do inherit(x); y = x + 1 end` | Attribute bindings with lexical inheritance |
| `rec(%{x: 1, y: x + 1})` | Recursive attributes |
| `let do inherit(scope, [:x]); x + 1 end` | Let bindings with scoped inheritance |
| `fn args = exact(%{x: x}) -> x end` | Strict argument set with a whole-argument binding |
| `%{key => value}` | Dynamic attribute name |
| `get(value, ["key"], fallback)` | Attribute selection with a lazy fallback |
| `has?(value, ["key"])` | Attribute existence |

Nix semantics still apply: `1 / 2` is integer division, boolean operators require
booleans, and interpolation uses `builtins.toString` (`true` becomes `"1"`;
`false` and `nil` become `""`). Literal shell `${VARIABLE}` text is preserved.
`[]` is an empty list; `%{}` is an empty attribute set.

`import_nix(...)` and a module's `imports: [...]` are distinct operations. Elixir
Streams can defer finite generation-time work; Nix evaluates the emitted syntax
lazily after generation. Arbitrary Elixir calls inside the DSL are rejected;
use `splice(...)` for explicit host computation.

## Run the built-in demo and tests

```sh
./test
./result/bin/nix-ex demo ./demo-nix
nix eval --offline --json path:./demo-nix#answer
# 42
./result/bin/nix-ex check-demo ./demo-nix
# Generated tree matches.
```

The [six runnable examples](examples/README.md) cover recursion, assets, module
merging, overlays, finite Streams, and an intentional runtime error. The suite
executes the README's Elixir snippets, evaluates all six examples, compares the
built-in demo with handwritten Nix, and checks CLI output drift. A source check
also keeps constructor boilerplate out of ordinary examples and the demo.

`./build` runs checks in Nix's sandbox and packages the CLI. The toolchain pins
Nixpkgs `f13ff45afd1bb73e640eaa08a7066dbed07e3238`, Elixir 1.18.4 and OTP
27.3.4.16, with four BEAM schedulers. The flake declares `x86_64-linux`,
`aarch64-linux`, and `aarch64-darwin`; execution has been verified on x86_64 Linux.
The [CI manifest](.mechatron-prime/targets) selects the Linux package and checks.
See [CI setup and verification](docs/CI.md) for webhook provisioning and
exact-commit status commands.

## Current limits

This is a prototype. The [coverage matrix](docs/PROTOTYPE.md#coverage) distinguishes
implemented syntax, evaluator-tested behavior, and gaps. Map-pattern renaming,
nested destructuring, guards, and multiple function clauses are unsupported.

Elixir syntax errors retain their original file and line. Nix runtime errors
report generated coordinates, with nearby source comments as manual hints.
[Automatic error remapping is not implemented](docs/ERROR_LOCATIONS.md).

The [migration guide](docs/MIGRATION.md) provides tested commands for converting
existing Nix into editable Elixir. A complete private configuration with 49
expressions and 84 supporting files now regenerates from Elixir alone and
evaluates to a system derivation. Recursive comparison explains every derivation
difference through one relocated policy-file path; the guide records the limits
of that evidence. All 49 expressions now migrate without explicit AST nodes,
including inherited bindings, strict patterns and multiline scripts. No host
activation has been performed. Migration is a starting point for editing;
comments and original formatting are not preserved.

See the [acceptance plan](docs/ACCEPTANCE.md) for the verification criteria.

Examples and tests use synthetic configurations. Generating or evaluating them
does not activate a system, change services, or deploy a configuration.
