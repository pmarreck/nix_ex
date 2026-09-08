import NixEx.DSL
alias NixEx.Project, as: P

# The multi-argument lambda emits final: prev: and keeps the fixed point in Nix.
overlay =
  nix do
    fn final, prev ->
      %{answer: prev.answer + 1, description: "answer=#{final.answer}"}
    end
  end

result =
  nix do
    let base: %{answer: 41},
        final: base |> Map.merge(import_nix(ref("overlay.nix")).(final, base)) do
      final
    end
  end

[P.nix("default.nix", result), P.nix("overlay.nix", overlay)]
