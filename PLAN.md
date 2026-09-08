# nix_ex investigation

Started 2026-09-08 06:46 EDT. Peter requested a delegated best-shot prototype.

## First prototype

- [x] Research Elixir AST/macros and Nix expression/module semantics using
  primary sources; document the generation-time versus evaluation-time boundary.
- [x] Establish a Nix-pinned Elixir/Mix project with a single `./test` command,
  development shell, package/check outputs, and no undeclared network dependency.
  Package sandbox checks passed 2026-09-08 07:09 EDT.
- [x] Implement and test a structured Nix AST and renderer, then a thin macro DSL. (2026-09-08 06:59 EDT)
- [x] Demonstrate Nix laziness, recursive bindings, functions and interpolation;
  explicitly investigate why Elixir Stream is or is not appropriate at each stage.
- [x] Generate a multi-file project with imports, nested modules and support
  assets. Test relocation, spaces in paths, escaping and output path safety.
- [x] Evaluate a synthetic NixOS module tree with merging, defaults/overrides,
  option definitions, arguments and conditional configuration using Nixpkgs.
- [x] Preserve useful source-location information; document what error mapping
  is implemented versus only designed.
- [x] Document syntax coverage and missing pieces toward Thelio-scale parity. (2026-09-08 07:08 EDT)
- [x] Run the complete suite, inspect generated source and commit only passing
  work. Leave a reproducible demo and a durable handoff if unfinished.
  Final sandbox package build passed 2026-09-08 07:11 EDT; 22 tests plus CLI.

## Verified prototype handoff

- 2026-09-08 07:11 EDT: `./test` and sandboxed `./build` passed.
  Parent independently reran `./test`: 22 tests, zero failures, CLI passed.
- `nix flake check --all-systems --no-build` evaluated all declared output sets.
  Only x86_64 Linux executed tests/builds; ARM Linux and Apple ARM were evaluated.
- Installed CLI demo tree: `/tmp/nix-ex-prototype.WeW27x/tree`.
  Nix-only `#answer` is 42; `check-demo` confirms unchanged generation.
- Source origins are basename/line comments; automatic span/error translation
  remains unimplemented. See `docs/PROTOTYPE.md` for the coverage matrix.
- Publication supports new or byte-identical trees. Changed output replacement,
  adversarial filesystem races, automatic stale-lock recovery, and complete
  Thelio translation remain outside this first prototype.

## Independent PM work

- [x] Inventory the actual Thelio flake/module constructs without changing the
  host or copying sensitive values (Einstein owns docs/THELIO_REQUIREMENTS.md).
- [x] Define staged acceptance criteria and non-vacuous evaluation comparisons
  (Einstein owns docs/ACCEPTANCE.md).

## Eventual acceptance target, not an initial completion claim

- [ ] Express the complete Thelio configuration tree through the DSL without
  using raw Nix strings or importing the original configuration as the answer.
- [ ] Compare relevant evaluated options and derivation identities against an
  exact pinned source baseline, accounting explicitly for source-path changes.
- [x] Make an ordinary generated flake consumable with Nix alone and verify
  reproducible regeneration and a clean generated-output diff gate.
  Synthetic prototype proven; future full host translation still required.
- [ ] Only after separate Peter approval, plan a real host migration. Until
  then, no activation, service changes or writes to `/etc/nixos` are authorized.
