# nix_ex investigation

Started 2026-09-08 06:46 EDT. Peter requested a delegated best-shot prototype.

## Elixir authoring ergonomics

Peter clarified the product goal on 2026-09-08: make Nix appealing to Elixir
developers who find it off-putting. Corresponding Elixir forms should be
simpler where possible; AST-constructor verbosity is a usability gap.

- [x] Agree on quoted attribute access, function-call syntax, and explicit module arguments.
- [x] Add failing evaluator-backed tests for the agreed syntax, including scope,
  nested attributes, curried applications, and the host/Nix execution boundary.
- [x] Implement the syntax and rewrite example 03 to demonstrate simpler authoring.
- [x] Run the complete suite and sandbox build, update syntax documentation, and commit.

Completed 2026-09-08 16:04 EDT. Six new behavior tests failed on unsupported
syntax before implementation. The complete suite now passes 35 tests plus CLI
checks for all six examples; the sandbox package build also passed. Example 03
uses direct dotted calls and module map patterns. Optional arguments still need
`N.pattern/2`; map-pattern renaming and nested destructuring remain unsupported.

Curiosity checks: `lib` must remain lexically bound, custom namespaces should
work too, and keyword shorthand must have a clear meaning beside Nix lists.
Existing source-map and Thelio parity milestones remain below.

## Runnable examples follow-up

- [x] Add tests that fail until six standalone example generators exist.
- [x] Add macro/laziness/recursion, multifile assets, module merges, overlay,
  finite Stream and intentional-error examples with checked expected results.
- [x] Include examples in sandbox checks and verify CLI generation from another cwd.
- [x] Document commands and current error locations; keep source-map implementation future.
- [x] Run complete tests/build and commit passing example work locally.

Verified 2026-09-08 11:27 EDT: 28 tests and CLI generation of all six examples
passed in the pinned shell and sandboxed package build. Parent independently
reran the full suite and installed examples 01/06. Nix runtime coordinates
remain generated-file coordinates; original-line annotations are manual hints.

Curiosity checks: ensure asset reads use `__DIR__`, streams remain finite, an
intentional failure is forced by Nix, and module inputs retain the existing pin.

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

- [ ] Add generated-span source maps and translate Nix runtime error locations
  to unambiguous original Elixir paths/lines (future work, not implemented here).

- [ ] Express the complete Thelio configuration tree through the DSL without
  using raw Nix strings or importing the original configuration as the answer.
- [ ] Compare relevant evaluated options and derivation identities against an
  exact pinned source baseline, accounting explicitly for source-path changes.
- [x] Make an ordinary generated flake consumable with Nix alone and verify
  reproducible regeneration and a clean generated-output diff gate.
  Synthetic prototype proven; future full host translation still required.
- [ ] Only after separate Peter approval, plan a real host migration. Until
  then, no activation, service changes or writes to `/etc/nixos` are authorized.
