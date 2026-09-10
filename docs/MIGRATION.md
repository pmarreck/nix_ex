# Migrate an existing configuration

`NixEx.Migrate` converts existing Nix expressions into editable Elixir once.
The resulting `.exs` files regenerate ordinary Nix through `NixEx.Project`.
Regeneration needs neither the original expressions nor the migration parser.

Start from a private snapshot of your complete configuration. Preserve its lock
file, supporting assets, executable bits, symlink targets and source revision.
Include uncommitted files that the configuration actually uses. Keep that
snapshot available for independent comparisons.

## A complete single-file example

Suppose `existing-config/default.nix` contains `{ answer = 42; }`. Save this as
`migrate.exs` beside `existing-config`, then run `nix develop -c mix run migrate.exs`
from the nix_ex checkout (use the script's absolute path if it lives elsewhere).

<!-- example: migrate -->
```elixir
source_root = Path.expand("existing-config", __DIR__)
output = Path.expand("elixir-config", __DIR__)

elixir =
  Path.join(source_root, "default.nix")
  |> NixEx.Migrate.from_file(root: source_root)
  |> NixEx.Migrate.to_elixir()

File.mkdir_p!(output)
File.write!(Path.join(output, "default.nix.exs"), elixir)
```

The migration script writes its destination file, so use a fresh directory.
Review and edit `elixir-config/default.nix.exs`. Then save the following as
`elixir-config/generate.exs`:

<!-- example: regenerate -->
```elixir
alias NixEx.Project, as: P

{expression, _} = Code.eval_file(Path.join(__DIR__, "default.nix.exs"))
[P.nix("default.nix", expression)]
```

Generate and evaluate with:

```sh
./result/bin/nix-ex generate /absolute/path/elixir-config/generate.exs ./generated-config
nix-instantiate --eval --strict --json ./generated-config/default.nix
# {"answer":42}
```

The test suite executes both snippets, hides the original source, and runs the
documented generator through the CLI.

## Complete trees

Inventory every expression explicitly, including extensionless imports. Call
`from_file/2` with the same snapshot root for each file. Keep each relative
filename when declaring `P.nix(relative_name, expression)`. Copy supporting
files into the Elixir project's asset directory and declare their bytes with
`P.asset(relative_name, bytes, mode: 0o644)` or `mode: 0o755`.

References inside the snapshot become project references. Existing referenced
directories need corresponding declared descendants. Paths outside the snapshot
remain absolute. Originally missing paths stay computed, lazy paths: a dormant
broken import remains broken when forced. The migration does not invent files.
Symlinked expressions can be materialized as translated files; this changes
file type and source identity, so inventory and compare that explicitly.

The importer asks `nix-instantiate --parse` to normalize syntax without evaluating
imports. Its parser targets the Nix version pinned by this project. It rejects
syntax it cannot represent, with no raw-Nix fallback. Comments, formatting and
original source positions are lost. Search-path lookups such as `<nixpkgs>` are
unsupported; use explicit pinned inputs.

Ordinary functions, calls, maps, bindings and conditionals use the quoted DSL.
`with_nix scope do ... end`, `assert_nix condition do ... end`, and
`var("a-name-with-dashes")` preserve Nix constructs that need explicit names.
Strict argument patterns, whole-argument bindings, inheritance, recursive sets,
dynamic keys and interpolated strings may use `splice(NixEx.AST.node(...))`.
These are structured expressions, but their emitted Elixir still needs ergonomic
cleanup. Migration preserves behavior before attempting authoring simplification.

## Evidence from a complete private configuration

On 2026-09-09, a local working-tree snapshot supplied 49 expressions and 84
supporting files. All expressions translated without raw Nix. The resulting
Elixir project regenerated all 133 files with the original expression directory
unavailable; repeated generation agreed byte for byte and asset executable
status matched. Generated files use modes 0644 or 0755; the private snapshot
itself has more restrictive permissions.

Both original and generated NixOS configurations evaluated to system derivations.
A mutable upstream version URL had drifted from its lock; the original bytes
were recovered and verified against the exact locked NAR hash. Both evaluations
used that same content through a local URL override without changing either lock.

Five derivation identities differed. Recursive comparison traced all five to
one service's policy-file path inside the flake source directory. The policy
bytes and mode were identical. Enumerated substitutions for that exact file
path and its dependent derivation/output paths made all five derivation records
identical; there were no unmatched dependencies or unexplained differences.
This establishes evaluation equivalence subject to that explicit path change.
It does not establish byte-identical source trees or runtime activation results.

The option comparison covered 515 system packages, all configured user package
lists, 174 systemd units, 186 `/etc` entries, 11 filesystems, boot settings,
firewall settings and five service enable flags. The only differences were the
same policy path in a unit and the resulting system-unit directory path.
A deliberate hostname change in the Elixir expression changed Nix's evaluated
hostname, confirming that the generated configuration responds to its Elixir input.

Private source, generated configuration and detailed comparison records stay
outside this public repository. Public tests use synthetic configurations and
the real Nix evaluator. Before adopting any migrated configuration, compare its
evaluated settings and derivations against its own pinned baseline, then change
an Elixir setting and verify that the comparison detects it. See the
[acceptance criteria](ACCEPTANCE.md) for the separate host-cutover boundary.
