# Acceptance and falsification plan

Written independently of the prototype implementation on 2026-09-08 EDT.
These are requirements, not a claim that all tests below already exist.

## What counts as progress

| Stage | Passing evidence | Insufficient evidence |
| --- | --- | --- |
| Expression generator | Generated expressions parse and evaluate correctly in real Nix | Renderer snapshots alone |
| Macro syntax | A documented Elixir subset produces the intended expression tree; unsupported syntax fails | Swallowing arbitrary AST or treating every value as a string |
| Multi-file project | Imports and assets resolve after moving the generated tree | Success only from the author's cwd |
| Module integration | A pinned Nixpkgs module evaluator agrees with an independent handwritten module | Merging Elixir maps or importing the golden module as the generated answer |
| Thelio coverage | Construct inventory, translated files and evaluation comparisons with explicit gaps | A raw-string wrapper around the old configuration |
| Host migration | Separate approved cutover and rollback plan | Running `nixos-rebuild switch` as a test |

## Three evaluation stages must stay distinct

**Elixir generation:** macros and ordinary functions create expression data.
Streams can defer enumeration of a collection of declarations. Explicit
generation-time code is ordinary trusted executable code; a DSL does not make
arbitrary `.exs` input a security sandbox.

**Nix evaluation:** the generated source retains lazy Nix expressions, recursive
bindings, import semantics and module merging. A symbolic `throw` remains code
until Nix demands it. Do not implement target laziness by accidentally executing
ordinary eager Elixir function arguments first.

**Build execution:** derivation scripts execute later in Nix's build environment.
Shell variable expansion and Nix interpolation in those scripts are different
operations and need separate escaping tests.

Primary references:

- [Elixir quoted expressions](https://elixir.hexdocs.pm/quote-and-unquote.html)
- [Elixir Stream](https://elixir.hexdocs.pm/Stream.html)
- [Nix language](https://nix.dev/manual/nix/2.34/language/index.html)
- [NixOS manual](https://nixos.org/manual/nixos/stable/)

## Test families

### Delayed expressions and scope

- An unused Nix `throw` binding must not fail generation or a successful Nix
  projection; explicitly selecting it must fail in Nix.
- A dead conditional branch containing a failure must stay unevaluated. Flip
  the condition and assert failure so the test cannot pass by dropping branches.
- A lazy unused self-reference must be representable; forcing a recursive cycle
  must fail instead of hanging the generator.
- Verify lexical shadowing, nested lambdas, recursive let references, attribute
  defaults, whole-argument bindings, dynamic keys, and missing required arguments.
- Host-stage Stream tests may prove delayed enumeration but must not be counted
  as target-stage lazy-evaluation coverage.

### Values, escaping and operators

- Round-trip strings containing literal `${...}`, Elixir `#{...}`, quotes,
  backslashes, newlines and Unicode through the real evaluator.
- Cover distinctions among identifiers, static/dynamic attribute names, strings
  and paths. A string containing an apparent Nix expression remains a string.
- Compare operator precedence and associativity against handwritten expressions;
  parentheses in generated output are acceptable if semantics are preserved.
- Test null, booleans, numeric limits and invalid values explicitly. Never
  silently render an unsupported value using an inspection/debug string.

### Multi-file projects

- Nested module imports, normal expression imports with arguments, directory
  `default.nix`, and extensionless expression files must work.
- Generate once, then move the tree under a path containing spaces and evaluate
  from a different working directory with no original generated tree available.
- Include an asset read from a nested module, a path interpolated into a string,
  and a script containing shell expansion syntax that must survive unchanged.
- Change a referenced asset and assert the evaluator observes the new contents;
  this rejects an implementation that embeds a stale golden output.
- Reject duplicate outputs, parent traversal and file/directory collisions.
  Check pre-existing output and symlink behavior; assert failures preserve
  unrelated files. Test failure after at least one valid planned entry.

### NixOS semantics

Use pinned Nixpkgs `lib.evalModules` for fast synthetic tests before considering
a full `nixosSystem` evaluation. Include typed options, multiple contributors,
`mkDefault`, `mkForce`, ordered list merging and `mkIf` conditions depending on
`config`. Include both valid and deliberately invalid option assignments.

The expected answer comes from a separate handwritten Nix fixture. Mutating a
DSL option should cause a meaningful difference, proving the comparison is not
just evaluating the same original file twice. Nix itself is the external
semantic oracle; shared authorship of a renderer and snapshot test is weaker.

### Determinism, diagnostics and coverage

- Generate twice with the same explicit inputs and compare all output bytes.
- Change enumeration order without changing the logical configuration and
  require stable output where ordering is not semantically significant.
- A regeneration check must fail when a generated artifact has drifted.
- A runtime Nix failure should expose the generated filename and a usable
  route to the originating Elixir file/line. State whether the prototype offers
  comments, a sidecar mapping or actual error translation.
- Coverage documentation distinguishes AST support, macro sugar, parsed-only
  syntax, evaluator-tested semantics and unsupported features.

## Resource and authority limits

Keep ordinary tests bounded and local. Do not build Thelio's full system or
reevaluate its whole dependency tree per test. Use synthetic modules and an
injected, already-pinned Nixpkgs source. Do not launch watchers or repeat network
fetches merely to keep the test loop running.

A future local Thelio parity command must be opt-in, read-only, pin both source
revisions and tool versions, capture stderr/exit status, and list exactly which
options/derivations were checked. Private hardware and credentials stay out of
the public fixture corpus. Derivation differences caused by source relocation
must be explained individually rather than erased by an overbroad normalizer.

## Independent prototype verification

Observed by the parent agent on 2026-09-08, recorded at 07:12 EDT
(`2026-09-08T07:12:00-04:00`):

- `./test`: 22 tests, zero failures; CLI smoke passed (ExUnit seed 436426).
- The installed `result/bin/nix-ex` generated a fresh multi-file demo.
- Nix alone evaluated the generated flake's `answer` to `42`.
- The installed CLI's `check-demo` confirmed that the tree matched.
- The generated modules, evaluated with the pinned Nixpkgs, returned
  `enable=true`, `greeting="hello world"`, `items=["first", "last"]`, and
  `priority="forced"`.
- `git diff --check` reported no whitespace errors.

The delegated implementation's final sandboxed build also passed the 22-test
suite and CLI smoke check. Its implementation commit is
`5dee2042cd4a8117dd6c51ce949de12654898943`.
These results establish a working prototype, not full coverage of every test
family proposed above or parity with Thelio's real configuration.
