import NixEx.DSL
alias NixEx.AST, as: N
alias NixEx.Project, as: P

# splice is Elixir-time computation; the condition and throw remain Nix syntax.
base = 40

answer =
  nix do
    if true do
      splice(base) + 2
    else
      throw("this branch is unused")
    end
  end

factorial =
  nix do
    let fact: fn n ->
          if n == 0 do
            1
          else
            n * apply(fact, [n - 1])
          end
        end do
      apply(fact, [6])
    end
  end

[P.nix("default.nix", N.attrs(answer: answer, factorial: factorial))]
