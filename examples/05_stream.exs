alias NixEx.AST, as: N
alias NixEx.Project, as: P

# Finite Elixir enumeration generates files; multiplication is evaluated by Nix.
values = Enum.map(1..3, fn n -> N.import_(N.ref("values/#{n}.nix")) end)
generated_values = Stream.map(1..3, fn n -> P.nix("values/#{n}.nix", N.op("*", 10, n)) end)

flake =
  N.attrs(
    description: "Finite Stream-generated Nix expressions",
    outputs: N.fn_(N.pattern(["self"]), N.attrs(values: N.import_(N.ref("default.nix"))))
  )

Stream.concat([P.nix("default.nix", values), P.nix("flake.nix", flake)], generated_values)
