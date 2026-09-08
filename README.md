# nix_ex

An experimental Elixir DSL that generates ordinary, relocatable Nix source
trees. The prototype implements structured expressions, a small quoted macro
subset, multiple files and assets, and real Nixpkgs module evaluation.

The goal is to express configurations as complicated as Peter's Thelio NixOS
configuration in Elixir, including a flake, multiple imported modules, overlays,
derivations, and their supporting files. This is an investigation, not a claim
that the full configuration has already been translated.

Elixir constructs a Nix expression tree; Nix evaluates it. Tests retain unused
throws, recursive bindings and delayed function arguments until Nix forces
them. Elixir streams defer generation-time enumeration only.

## Try it

```sh
./test
./build
./result/bin/nix-ex demo /tmp/nix-ex-demo
nix eval --json path:/tmp/nix-ex-demo#answer
# 42
./result/bin/nix-ex check-demo /tmp/nix-ex-demo

# Evaluate the generated modules with this project's pinned Nixpkgs:
nix develop -c bash -c 'nix-instantiate --eval --strict --json /tmp/nix-ex-demo/default.nix --arg nixpkgs "$NIX_EX_NIXPKGS"'
# {"enable":true,"greeting":"hello world","items":["first","last"],"priority":"forced"}
```

Use a fresh destination whose parent exists. An identical existing tree is a
successful no-op; changed trees are refused. `check-demo` returns nonzero on
drift. Generate to another directory to review a changed result. On macOS use
canonical paths such as `/private/tmp`, because symlink ancestors are refused.

The toolchain pins Nixpkgs `f13ff45afd1bb73e640eaa08a7066dbed07e3238`,
Elixir 1.18.4 and OTP 27.3.4.16, with four BEAM schedulers. The flake declares
`x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`; only x86_64 Linux has been
run here. `./test` runs all suites in the pinned shell. `./build` builds the
package and runs checks inside Nix's sandbox.

See the [prototype guide and coverage matrix](docs/PROTOTYPE.md) for the DSL,
generation safety, supported semantics, and diagnostic limitations.

There are now [six runnable example generators](examples/README.md), covering
macros and recursion, imports/assets, module merging, overlays, finite Streams,
and an intentional Nix error. Each has checked expected results.

Elixir DSL syntax errors retain their original file and line. Nix runtime
errors currently report generated Nix coordinates, with nearby source comments
as manual hints. There is no automatic remapping; see
[verified error locations](docs/ERROR_LOCATIONS.md).

## Requirements

- Represent all Nix expression forms through explicit AST constructors, with
  ergonomic macros for common cases and explicit unsupported-syntax errors.
- Generate a relocatable tree of files, not just a single string.
- Distinguish Nix `import` from the NixOS module system's `imports` option.
- Preserve relative paths, assets, interpolation, recursion, binding and scope.
- Let generated files work with Nix alone, with no Elixir evaluation dependency.
- Use the real Nix evaluator as a test oracle, including dead-branch laziness,
  imports across directories, module priorities and deterministic regeneration.
- Preserve source-location information for useful diagnostics.
- Never activate, switch, rebuild for deployment, or overwrite a live host
  configuration as part of this experiment.

See [PLAN.md](PLAN.md) for milestones and honest completion status.
The independent [Thelio inventory](docs/THELIO_REQUIREMENTS.md),
[acceptance criteria](docs/ACCEPTANCE.md), and [prior art](docs/PRIOR_ART.md)
define the remaining investigation.

## Working boundary

`/etc/nixos` on Thelio is read-only reference material for this project. Its
configuration, private data, secrets, and host-specific identifiers must not be
copied into public fixtures. Tests should use synthetic equivalents, with a
separately opted-in local comparison against the real configuration later.

No GitHub repository has been created or publication authorized yet.
