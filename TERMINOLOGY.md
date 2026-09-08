# Project terminology

Definitions extracted from the former project overview; project purpose lives
in [INTENT.md](INTENT.md).

- **AST**: the project's data representation of Nix syntax, used by the renderer
  and for advanced composition.
- **Macro DSL**: the Elixir surface syntax that constructs that AST. Its Nix
  expressions are not ordinary eager Elixir evaluation.
- **Output identity**: a project-relative filename in a generated output tree.
- **Source-relative reference**: a reference resolved from the generated file
  containing it, rather than from the generator's working directory.
- **Generation**: Elixir constructs and emits the Nix source tree.
- **Nix evaluation**: Nix evaluates the generated expressions.
- **Derivation build execution**: build instructions execute later in Nix's
  build environment. This is separate from both generation and evaluation.
