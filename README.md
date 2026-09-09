# nix_ex

[![Mechatron Prime CI](https://img.shields.io/endpoint?url=https%3A%2F%2Fthelio-nixos.tail66c90.ts.net%2Fbadges%2Fnix_ex.json&style=for-the-badge)](https://thelio-nixos.tail66c90.ts.net/mechatron-prime/)

Write Nix configurations in familiar Elixir syntax. Generate ordinary,
relocatable Nix files that work with Nix alone.

`nix_ex` is an experimental authoring layer for Elixir developers who find Nix
hard to approach. Inside `nix do`, a macro turns your expressions into Nix
syntax. Nix handles lazy evaluation, recursive bindings, and module merging.
Outside the block, you have ordinary Elixir for organizing and generating files.

[Project intent](INTENT.md) · [DSL guide](docs/PROTOTYPE.md) · [Examples](examples/README.md) · [Current work](PLAN.md)

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

The goal is to support complete NixOS configurations spanning flakes, modules,
overlays, derivations, and supporting assets. Full configuration translation
and parity comparison remain unfinished. See the
[acceptance plan](docs/ACCEPTANCE.md) for the verification criteria.

Examples and tests use synthetic configurations. Generating or evaluating them
does not activate a system, change services, or deploy a configuration.
