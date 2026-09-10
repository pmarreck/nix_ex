# Prototype guide

## Write a generator

The [runnable examples](../examples/README.md) provide six complete `.exs`
generators with expected results and automated checks. For actual syntax-error
and runtime-error output, see [error locations](ERROR_LOCATIONS.md).

Save this as `example.exs`, then run
`nix develop -c mix run -e 'NixEx.CLI.main(["generate", "example.exs", "/tmp/my-nix-tree"])'`.
Generator scripts are trusted Elixir programs with ordinary host access.

```elixir
alias NixEx.Project, as: P
import NixEx.DSL

generated_at_elixir_time = 40
entrypoint = nix do
  %{
    answer: splice(generated_at_elixir_time) + 2,
    imported: import_nix(ref("nested/value"), x: 41),
    text: builtins.readFile(ref("assets/message.txt"))
  }
end
value = nix do: fn %{x: x} -> x + 1 end

[
  P.nix("default.nix", entrypoint),
  P.nix("nested/value", value),
  P.asset("assets/message.txt", "shell ${HOME} survives unchanged\n")
]
```

`ref("nested/value")` inside `nix` names a project output from any generated file.
`source_path("../assets/message.txt")` resolves relative to the generated
source file. Both are Nix paths, emitted as path-plus-string expressions so
spaces and literal `${...}` in filenames stay safe. Directory references and
extensionless Nix files work. `source_path(".")` refers to the generated file's
directory. At the root entrypoint that is the output root.
`N.absolute_path(...)` explicitly sacrifices relocation. Computed Nix paths can
be expressed with ordinary operators; static output validation cannot predict
their eventual evaluation.

`import_nix(path)` imports an expression; `import_nix(path, x: 41)` imports and
applies it to an attribute set. The explicit name distinguishes it from Elixir's
module import. These helpers construct syntax and never read a file in Elixir.
For generation-time paths use `ref(splice(path))`. AST constructors `N.ref`,
`N.source_path`, and `N.import_` remain available outside the quoted DSL.
A NixOS module's
`imports` is an ordinary attribute containing paths or modules, evaluated by
Nixpkgs. These operations have different semantics and stay distinct.

The generated demo flake has no inputs and needs Nix alone for its `answer`
output. Its `lib.evaluateModules` accepts an explicitly supplied Nixpkgs path;
consuming generated files never invokes Elixir or import-from-derivation.
The demo module expects `enabled` and `token` through module arguments.

## Evaluation stages

Elixir constructs `%NixEx.Expr{}` data. `nix do ... end` captures a small syntax
subset using Elixir macros; `splice(...)` explicitly runs ordinary Elixir while
constructing that data. Unknown DSL forms, including Elixir module calls such
as `System.cmd(...)`,
raise `CompileError` with the original file and line. The macro supports
literals, lists, static-key maps, variables, binary operators, unary `!`/`-`,
`if` with both branches, lambdas, `let [name: value] do ... end`,
`apply(fun, [args])`, `get(value, ["attribute"])`, and `throw(message)`.

Dotted expressions use Nix scope: `lib.types.bool` selects an attribute and
`lib.mkOption(type: lib.types.bool, default: false)` applies a Nix function to
an attribute set. Bare `lib.mkOption` selects the function without applying it.
This works for any expression receiver, including custom namespaces and call
results such as `lib.types.listOf(lib.types.str).check(["first"])`. No Elixir
variable named `lib` is needed; the generated Nix still requires a binding.

Multiple positional arguments become curried Nix applications:
`builtins.add(19, 23)` emits the equivalent of `builtins.add 19 23`.
`fact.(6)` calls a function value, including recursively bound functions.
`fn final, prev -> ... end` becomes `final: prev: ...` in Nix. Partial application
is supported. `value |> f.(arg)` and `value |> lib.f(arg)` insert `value` as the
first argument, following Elixir's pipe order. Zero-argument functions, repeated
parameter names, guards, and multiple clauses are rejected.

Nonempty keyword lists in dotted/anonymous-call and import argument positions become attribute sets,
including explicitly bracketed `[type: lib.types.bool, default: false]`.
Elixir's quoted AST does not distinguish that spelling from trailing keywords.
Ordinary lists remain lists; `[]` is an empty list and `%{}` is an empty set.
Zero-argument calls such as `lib.mkOption()` are rejected; use bare attribute
selection to retain a function value. These conventions belong to the quoted
DSL and do not change ordinary Elixir execution outside it.

Module functions can use `fn %{lib: lib, config: config} -> ... end`, which
emits a Nix `{ lib, config, ... }: ...` function. The named arguments are
required and extra arguments are accepted, matching Elixir map patterns.
The current subset requires each key and bound variable to have the same name;
renaming, nested patterns, and duplicate keys are rejected. Optional arguments
use `\\`, for example:

```elixir
nix do
  fn %{nixpkgs: nixpkgs, enabled: enabled \\ true} ->
    # ...
    enabled
  end
end
```

This is quoted DSL syntax; ordinary Elixir map patterns do not support defaults.
Defaults remain Nix expressions, can refer to other arguments, and are forced
only when needed. Explicit `false` or `nil` overrides the default.
See example 03 for complete module declarations.

`Map.merge(left, right)` is the supported Elixir-module-call exception. It emits
Nix's shallow, right-biased `//` update, including lazy recursive overlays.
Other `Map` calls and the three-argument Elixir merge are unsupported.

`with_nix scope do ... end` and `assert_nix condition do ... end` emit Nix's
`with` and `assert` expressions. Their bodies retain lazy Nix semantics.
`var("custom-name")` refers to identifiers that need an explicit string in
Elixir. Quoted keyword keys work in `let`, including `let "custom-name": 42 do
var("custom-name") end`.

Inside `nix`, operators have Nix semantics: `1 / 2` is integer division and
`&&`/`||` require booleans. Arbitrary Elixir code is not transpiled.
AST constructors cover the richer Nix syntax listed below.

Nix evaluates emitted expressions lazily. Tests keep throws and recursive
cycles in unused bindings, branches and arguments, then force them in negative
controls. Recursive factorial and lexical shadowing are evaluated by Nix.
Constructors never try to implement Nix evaluation in Elixir.

Elixir `Stream` can defer generation of a finite output collection. A test
observes that no generator callbacks run until `Project.write/2` enumerates the
stream. The complete collection is consumed, validated and rendered before any
destination appears. A late generator exception publishes nothing. This is
generation-time laziness; it does not supply Nix's thunks, lexical scopes or
recursive fixed points. Infinite streams will not complete and are unsupported.
See [Elixir Stream](https://hexdocs.pm/elixir/1.18.4/Stream.html),
[quoted expressions](https://hexdocs.pm/elixir/1.18.4/quote-and-unquote.html), and
[Nix syntax and semantics](https://nix.dev/manual/nix/2.34/language/syntax.html).

Derivation scripts execute at a third stage, during a Nix build. Plain Elixir
strings preserve shell `${VARIABLE}` literally. Inside `nix`, `"answer=#{value}"`
interpolates a Nix expression using `builtins.toString`. Conversion follows Nix:
for example, `true` becomes `"1"`, and `false` or `nil` becomes `""`. This is not
Elixir's `String.Chars` protocol. Outside `nix`, interpolation is ordinary Elixir
generation-time work. `N.string(["prefix ", expr])` remains the explicit AST form.
The renderer uses escaped quoted Nix
strings, including for multiline text. It does not reproduce indented-string
source spelling or dedentation rules.

## Coverage

“Evaluated” means exercised through the real Nix evaluator in the suite,
not just compared with a generated-source snapshot.

| Construct | AST API | Evidence / boundary |
| --- | --- | --- |
| Null, booleans, signed 64-bit integers, floats | Elixir literals | Evaluated, integer min/max and overflow rejection |
| Strings, interpolation, Unicode | literals, `string/1` | Evaluated; UTF-8 without NUL; shell expansion remains literal |
| Lists, attribute sets, recursive sets | lists, maps, `attrs/2` | Evaluated; maps sort keys; explicit binding order retained |
| Static, dotted and dynamic attribute names | binding paths, `dynamic/1` | Evaluated; static duplicates rejected; Nix diagnoses semantic conflicts |
| Selection, fallback, attribute existence | `select/2,3`, `has/2` | Evaluated |
| Recursive let and lexical scope | `let/2`, `var/1` | Evaluated, including unused/forced cycles and recursion |
| Simple/curried functions and applications | `fn_/2`, `call/2` | Evaluated, including overlay-shaped functions |
| Set argument patterns, defaults, ellipsis, `@` | `pattern/2` | Evaluated; `@` renders after the pattern |
| `inherit`, scoped `inherit`, `with`, `assert` | `inherit_/1,2`, `with_/2`, `assert_/2` | Evaluated |
| Binary operator families, `!` and negation | `op/3`, `unary/2` | Evaluated; fully parenthesized output |
| Conditional and short-circuit evaluation | `if_/3`, boolean operators | Evaluated with forced-failure controls |
| Relative paths, imports, assets, directory defaults | `ref/1`, `source_path/1`, `import_/1,2` | Evaluated after relocation; path interpolation tested |
| Modules, typed options, priorities, ordered list merge | ordinary function/attribute AST | Pinned `lib.evalModules`, handwritten comparison, changed-input and invalid-type controls |
| Flake syntax and outputs | ordinary function/attribute AST | Generated no-input flake evaluated with Nix alone |
| Derivations, fetchers, `callPackage`, `overrideAttrs` | ordinary function/attribute AST | Complete private configuration translated and evaluated; [comparison evidence](MIGRATION.md#evidence-from-a-complete-private-configuration) |
| Absolute paths | `absolute_path/1` | Implemented, intentionally not relocatable |
| Search-path lookup `<name>`, deprecated URI literal spelling | none | Unsupported; use explicit pinned paths and strings |
| Comments, formatting preservation, source-position identity | origin annotations only | One-time migration parser exists; original formatting and positions are not preserved |
| Raw escape hatch | `raw_nix/1` | Unvalidated, never counted as expression coverage |

## Output safety and diagnostics

The generator validates every output identity, duplicate, file/directory
collision, static reference and rendered expression before publishing. Assets
are explicit bytes with mode 0644 or 0755; input directory copying and symlink
assets are unsupported. A private staging tree is renamed into a fresh
destination. Cooperating writers use a sibling lock directory. Failure removes
only that private staging/lock tree. Process death can leave a stale lock that
must be inspected before manually removing it.

Existing trees are compared against the expected directory skeleton, failing
immediately on unexpected children; unrelated directories are not traversed.
Filesystem root and the current home directory are refused. Destination
symlinks and symlink ancestors are refused. On macOS use canonical paths such
as `/private/tmp`, since `/tmp` and `/var` commonly contain system symlinks.
Publication is not a security boundary against noncooperating processes racing
filesystem changes; portable atomic no-replace directory publication and
durability across power failure remain open work.

Macro nodes carry stable basename/line origin labels and render nearby
`# nix-ex source: file.exs:line` comments. `N.at(expr, "logical-source.exs", line)`
annotates explicit AST nodes. Runtime errors retain Nix's generated filename;
inspect that file's origin comments to find the Elixir declaration. There is
no sidecar span map or automatic error rewriting, and equal basenames can be
ambiguous. The built-in demo uses macro origins from its actual declarations.
Generated source positions and paths can be observable
in Nix, so expression coverage does not prove universal identity.

The [migration guide](MIGRATION.md) records the complete private translation,
its pinned derivation comparisons and the remaining authoring and runtime gaps.
See [the independent acceptance plan](ACCEPTANCE.md) for the verification criteria.
