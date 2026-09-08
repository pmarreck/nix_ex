# Project intent

## Purpose and audience

Investigate whether Elixir can comfortably express and maintain a NixOS
configuration as complex as Thelio's while generating normal Nix source files
that remain independently usable with Nix.

The intended audience is Elixir developers who are put off by Nix. Make the
Elixir forms simpler than their corresponding Nix expressions where possible.
The structured AST supports implementation and advanced composition; ordinary
authoring should avoid exposing its constructor boilerplate.

## Desired outcomes

- Author ordinary Nix configurations in readable Elixir forms, with explicit
  escape into syntax constructors for advanced composition.
- Generate complete multi-file trees, including modules, imports, overlays,
  derivations and supporting assets, that Nix can consume without Elixir.
- Preserve Nix evaluation behavior, including laziness, recursion and relative
  references. Keep Elixir generation and Nix evaluation distinct.
- Eventually express the full Thelio configuration, with demonstrated parity
  rather than a wrapper that imports the existing configuration as its answer.

These are intended outcomes, not a claim that full translation is complete.

## Constraints and evidence

[RULES.md](RULES.md) owns the engineering and safety constraints, including
the read-only boundary around the live host configuration. This intent does not
authorize a host migration or activation.

[Acceptance criteria](docs/ACCEPTANCE.md) define staged evidence, including
real Nix evaluation and independent comparisons. The
[Thelio requirements](docs/THELIO_REQUIREMENTS.md) inventory the eventual target.
Authoring ergonomics must also be assessed through representative examples;
semantic correctness alone does not establish that the DSL is pleasant to use.

## Related documents

- [TERMINOLOGY.md](TERMINOLOGY.md) defines project vocabulary.
- [PLAN.md](PLAN.md) records current tasks, progress and unresolved implementation work.
- [Prototype guide](docs/PROTOTYPE.md) documents current syntax and limitations.
- [Examples](examples/README.md) provide runnable authoring and evaluation cases.

This document preserves the purpose and audience recorded in
`PROJECT_OVERVIEW.md` at commit `02c7678efe34be8d78515c8874af186e66922f9d`,
migrated under Peter's 2026-09-08 project-document instruction. Substantive
purpose changes require his direction; ordinary task progress belongs in the plan.
