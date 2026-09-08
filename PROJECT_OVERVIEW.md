# Project overview

Investigate whether Elixir can comfortably express and maintain a NixOS
configuration as complex as Thelio's while generating normal Nix source files
that remain independently usable with Nix.

The AST is a data representation of Nix syntax. The macro DSL is an optional
Elixir surface syntax that constructs that AST. An output identity is a
project-relative filename. A source-relative reference is resolved from the
generated file containing it. Generation, Nix evaluation, and derivation build
execution are separate stages.

The prototype proves expression rendering, lazy target semantics, multifile
output and synthetic module evaluation. A complete host translation,
source-map diagnostics and a production update workflow remain future work.
