# Error locations

Verified with the installed prototype on 2026-09-08 EDT. The current compiler
records source hints but does not translate Nix errors back to Elixir locations.

## Elixir DSL syntax errors

Unsupported syntax fails during generation. For example, putting
`String.upcase("unsupported call")` on line 5 inside `nix do ... end` reports:

```text
syntax_error.exs:5: unsupported nix syntax: String.upcase("unsupported call"); use AST constructors through splice/1
```

This uses the original Elixir file and line. The CLI preserves the location in
the exception message and exits unsuccessfully. No Nix output tree is published.

## Nix evaluation errors

This generator has a type error on Elixir line 5:

```elixir
import NixEx.DSL
alias NixEx.Project, as: P
expression =
  nix do
    1 + "wrong type"
  end
[P.nix("default.nix", expression)]
```

Generation succeeds because it constructs syntax. Evaluating the resulting
`default.nix` with `nix-instantiate --eval --strict --json --show-trace` fails:

```text
error: cannot add a string to an integer
       at generated/default.nix:3:6:
            2| # nix-ex source: runtime_error.exs:5
            3| (1 + "wrong type")
             |      ^
            4| )
```

Temporary directory prefixes are omitted from these diagnostic excerpts.
Nix's reported coordinate is **generated line 3, column 6**. The comment refers
to **Elixir line 5**. Nix happened to include that nearby comment in this excerpt;
it is not an automatic source-map lookup and will not always appear in an error.

## Boundaries

- Macro nodes carry the Elixir basename and line. They do not retain full
  source paths, columns, or a generated-span map.
- Two source files with the same basename can be ambiguous.
- Constructor-only expressions need explicit `N.at(expression, file, line)`
  annotations for these hints. There is no inferred original location for every
  value or manually constructed node.
- External Nixpkgs errors, module errors, and build-script failures may point
  outside generated files or have different kinds of context.
- The CLI currently generates and checks output trees. It has no Nix-evaluation
  wrapper that intercepts and translates evaluator diagnostics.

Before a full Thelio migration, a useful next step would be generated-span maps
with project-relative Elixir source identities and a diagnostic reader that
retains the original Nix error while adding mapped locations. Unknown or stale
mappings must remain explicitly unmapped. That feature has not been implemented.
