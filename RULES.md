# Project rules

- Keep `/etc/nixos` read-only. Never activate or deploy as a test.
- Keep private host values out of fixtures and generated examples.
- Preserve Nix evaluation semantics by emitting syntax, including delayed bodies.
- Make generation-time execution explicit. Do not pretend arbitrary Elixir is Nix.
- Test semantic claims against a pinned evaluator with negative controls.
- Publish complete validated trees. Never overwrite a changed existing tree.
- Keep generated files consumable with Nix alone.
- Do not introduce i18n or publish externally without Peter's decision.
