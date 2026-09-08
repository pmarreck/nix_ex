alias NixEx.AST, as: N
alias NixEx.Project, as: P

# Constructor-only AST needs an explicit annotation. Keep the actual source line.
failure = N.call(N.var("builtins.throw"), ["example intentionally fails"])
origin_line = __ENV__.line + 1
annotated = N.at(failure, Path.basename(__ENV__.file), origin_line)

# Generation succeeds. Nix reports default.nix coordinates when this is forced.
[P.nix("default.nix", annotated)]
