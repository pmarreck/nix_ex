import NixEx.DSL
alias NixEx.Project, as: P

# Finite Elixir enumeration generates files; multiplication is evaluated by Nix.
values = Enum.map(1..3, fn n -> nix(do: import_nix(ref(splice("values/#{n}.nix")))) end)
generated_values = Stream.map(1..3, fn n -> P.nix("values/#{n}.nix", nix(do: 10 * splice(n))) end)

flake =
  nix do
    %{
      description: "Finite Stream-generated Nix expressions",
      outputs: fn %{self: self} -> %{values: import_nix(ref("default.nix"))} end
    }
  end

Stream.concat([P.nix("default.nix", values), P.nix("flake.nix", flake)], generated_values)
