# Prior art and scope

Research checked 2026-09-08. This is a short survey, not a novelty claim.

## NiJS: Nix expressions from JavaScript

[NiJS](https://github.com/svanderburg/nijs) already demonstrates an internal DSL
for producing Nix expressions from another language. It distinguishes ordinary
JavaScript values from explicit Nix syntax nodes for functions, imports,
recursive sets, conditionals, and lexical bindings. Its README also describes
bridging back to JavaScript functions and invoking deployment operations.

For this experiment, the useful precedent is explicit syntax construction.
The proposed boundary is narrower: generate ordinary Nix files first, and let
Nix evaluate them. Consuming generated configuration should not require an
Elixir interpreter or callbacks into the generator.

This makes the investigation about whether Elixir's macros and composition
produce a usable, faithful authoring layer for a real NixOS configuration—not
whether generating Nix from another programming language is a new invention.

## Elixir quotation and Streams

[Elixir quotation](https://elixir.hexdocs.pm/quote-and-unquote.html) gives macros
access to syntax. That is useful for representing a Nix conditional without
executing the conditional as Elixir.

[Streams](https://elixir.hexdocs.pm/Stream.html) defer enumerable operations
until consumption. They can generate a large output plan incrementally. They
do not supply Nix's lexical scope, recursive bindings, or lazy evaluation.
Those remain represented in syntax and executed by the
[Nix evaluator](https://nix.dev/manual/nix/2.34/language/index.html).

These mechanisms address separate stages; neither should be advertised as a
drop-in implementation of the other's semantics.
