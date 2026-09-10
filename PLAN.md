# nix_ex investigation

Started 2026-09-08 06:46 EDT. Peter requested a delegated best-shot prototype.

## Readable migration output and short commands

Requested 2026-09-10. Preserve the verified private configuration while improving
its authoring forms and the public conversion/checking workflow.

- [x] Inventory remaining explicit AST forms and establish readable syntax with
  failing evaluator tests. Preserve strict patterns, inheritance and string context.
- [x] Emit the simpler DSL from migration and compare a fresh private translation
  against the verified system derivation.
- [x] Provide short conversion and checking commands with tested defaults,
  useful failures and paths containing spaces. Supply portable CLI commands and
  Nix flake apps; native plugin APIs require a matching Nix build.
- [x] Update runnable documentation, verify packaged commands, and run tests/build.
  Verified 2026-09-10 12:05 EDT: 75 tests, CLI smoke and sandbox build passed.
- [ ] Push and verify exact-commit CI.

All 49 private expressions now emit zero `AST.node` escapes. Source size fell
from 345,808 to 247,423 bytes. Inheritance, recursive bindings, strict and whole-set
patterns, dynamic keys and multiline Nix strings use DSL forms. The updated full
system evaluates; all five changed derivations are explained by the same relocated
policy path and dependent outputs, with no unexplained differences. The packaged
`convert` and `check` apps successfully ran against the private authoring project.
The short registry alias was tested in a private registry, not installed globally.

## Complete private configuration translation

Peter requested full Elixir reproduction on 2026-09-09. Public changes must
remain generic; host-specific sources, generated outputs and comparison data
belong outside this repository. No activation or source-host edits.

- [x] Capture a private, immutable working-tree baseline, including staged
  changes, with per-file hashes and source revision provenance.
- [x] Establish evaluator-backed failing tests for a one-time migration path
  that emits editable Elixir and rejects unsupported syntax explicitly.
- [x] Translate the complete local expression tree and supporting assets;
  generated Elixir must regenerate without reading original Nix expressions.
- [x] Compare pinned evaluated host options and derivation identities, with
  explicit path-sensitive differences and forced-change controls.
- [x] Document remaining gaps honestly and validate reusable tooling and
  synthetic fixtures. Completed 2026-09-09 23:16 EDT: 59 tests, CLI checks,
  sandbox package build and both CI manifest targets passed. Initialize the
  sandbox Nix store before parallel tests to avoid concurrent schema creation.
- [x] Push the reusable tooling and verify exact-commit CI; keep the complete
  translated configuration and comparison records private. Completed 2026-09-09
  23:18 EDT: `1fd6219cc12c565528a0394a451c1cc67af30f40` passed CI in 15 seconds;
  fetched `origin/yolo` matched. All 133 live source file hashes still match the
  captured baseline, and the packaged CLI reproduced the independent tree.

Verified 2026-09-09 23:10 EDT: 49 expressions and 84 assets regenerate with
the original source directory unavailable. Full system derivations evaluate;
five changed derivations trace to one source-relative policy path, with identical
policy bytes/mode and no unexplained differences. Compared 515 system packages,
all user package lists, 174 systemd units, 186 `/etc` entries, 11 filesystems,
boot/firewall settings and five service enable flags. An Elixir hostname mutation
changed the evaluated hostname. A drifted upstream version file was recovered
with its exact locked NAR hash; both evaluations used the same local URL override.
Detailed provenance and results remain private. See [migration guide](docs/MIGRATION.md).

## Public README wording

- [x] Replace personal host references with generic configuration goals and
  example safety boundaries. Preserve the CI badge and its URLs, as Peter
  explicitly requested on 2026-09-09.
- [x] Verify examples/build and push the README cleanup. Verified 2026-09-09
  19:15 EDT: 46 tests, CLI checks, and sandbox build passed.

## Documentation refresh and first publication

- [x] Check current docs and examples for stale claims; preserve dated evidence.
- [x] Add clear README examples and execute their snippets in the test suite.
- [x] Configure and build exact CI targets; create `pmarreck/nix_ex` on GitHub.
- [x] Commit, push to GitHub, and verify the remote commit.
- [x] Provision the repository webhook and verify the exact commit's CI result. Completed 2026-09-09 19:07 EDT.
  - Webhook 676882816 created, then `yolo` push `f5c75b1662d618f89bbe8082b7e256dd78884eb4` admitted and passed in 30s. `mechatron-ci log --project nix_ex --commit f5c75b1` reports `success`. Public badge `https://thelio-nixos.tail66c90.ts.net/badges/nix_ex.json` is `PASSING`.

Local verification 2026-09-09: 46 tests and CLI checks passed; sandbox package
build and both manifest targets passed. The new README test failed before its
three runnable snippets existed. Existing examples and diagnostic documentation
still match current behavior; the earlier defaults limitation is marked historical.
Webhook dry-run reports CREATE for this repository. Provisioning requires the
root-owned secret; this session's noninteractive sudo attempt was refused.
Peter has been given the scoped command in [docs/CI.md](docs/CI.md).

Published 2026-09-09 18:06 EDT at https://github.com/pmarreck/nix_ex, public,
with `yolo` as the default branch. Fetched `origin/yolo` matched publication
commit `7c9719c16e472844c7fe2956bea2afe7a02a2edd`. GitHub's Markdown renderer
confirmed three Elixir blocks and the syntax table's two columns; local README
links resolved. No webhook or CI result exists yet; the badge endpoint returns
404 until its first accepted build.

Peter requested publication on 2026-09-09. Check README snippets against real
Nix evaluation, and keep the existing host activation boundary intact.

## Further authoring simplification

Peter approved extending the simpler DSL on 2026-09-08.

- [x] Test and implement optional map-pattern arguments using `\\`, retaining
  lazy defaults and references to other arguments. Check overridden failures.
- [x] Test and implement anonymous calls, curried multi-argument lambdas and
  Elixir-style pipes. Check argument order, recursion and unsupported call forms.
- [x] Test and implement path/import helpers, interpolation and `Map.merge`.
  Check relocation, literal shell interpolation and lazy overlay recursion.
- [x] Rewrite the examples under their existing evaluation tests, document the
  syntax and boundaries, run the complete suite/build, and commit passing work.
- [x] Update the built-in demo's constructor-heavy modules to the same DSL and
  test demo/example authoring conventions as well as their evaluated behavior
  (Peter's follow-up during this work).

Completed 2026-09-08 16:44 EDT. Each syntax addition followed a failing evaluator
test. The authoring check first identified the built-in demo and five ordinary
examples as stale; all now use the quoted DSL. Example 06 intentionally retains
the explicit source-annotation API. Full suite: 45 tests plus CLI generation,
demo drift detection and all six examples from another cwd. Sandbox build passed.
Interpolation uses Nix's `builtins.toString`, not Elixir's `String.Chars` protocol;
map-pattern renaming, nested destructuring, guards and multiple clauses remain
unsupported. The demo's macro origins now point at actual declaration lines.

## Project-document pilot

- [x] Migrate the overview's purpose and audience to [INTENT.md](INTENT.md),
  extract definitions to [TERMINOLOGY.md](TERMINOLOGY.md), and keep progress here.
  Peter requested this convention on 2026-09-08. Original overview is recoverable
  from commit `02c7678efe34be8d78515c8874af186e66922f9d`.
- [x] Verify the documentation migration and existing suite before committing.
  Completed 2026-09-08 16:27 EDT: 35 tests passed, plus CLI smoke checks and
  six examples from another working directory; documentation links checked.

The former overview's status summary is preserved by the first-prototype and
future milestones below: expression rendering, lazy target semantics,
multifile output and synthetic module evaluation were demonstrated; complete
host translation, source-map diagnostics and production output updates remained
future work at the overview's recorded revision. This is a historical summary,
not a substitute for newer progress entries.

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
uses direct dotted calls and module map patterns. At this milestone optional
arguments still needed `N.pattern/2`; the later simplification above added
default syntax. Map-pattern renaming and nested destructuring remain unsupported.

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

- [x] Express the complete Thelio configuration tree through the DSL without
  using raw Nix strings or importing the original configuration as the answer.
- [x] Compare relevant evaluated options and derivation identities against an
  exact pinned source baseline, accounting explicitly for source-path changes.
- [x] Make an ordinary generated flake consumable with Nix alone and verify
  reproducible regeneration and a clean generated-output diff gate.
  Synthetic prototype and complete private host translation verified; see above.
- [ ] Only after separate Peter approval, plan a real host migration. Until
  then, no activation, service changes or writes to `/etc/nixos` are authorized.
