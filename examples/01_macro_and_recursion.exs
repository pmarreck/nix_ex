import NixEx.DSL
alias NixEx.Project, as: P

# splice is Elixir-time computation; recursion and the unused throw stay in Nix.
base = 40

result =
  nix do
    let fact: fn n ->
          if n == 0, do: 1, else: n * fact.(n - 1)
        end do
      %{
        answer:
          if true do
            splice(base) + 2
          else
            throw("this branch is unused")
          end,
        factorial: fact.(6)
      }
    end
  end

[P.nix("default.nix", result)]
