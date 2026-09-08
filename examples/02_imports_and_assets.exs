import NixEx.DSL
alias NixEx.Project, as: P

# __DIR__ makes reading a generator asset independent of the CLI's cwd.
message = File.read!(Path.join(__DIR__, "assets/message.txt"))

result =
  nix do
    fn %{x: x} ->
      %{
        answer: x + 1,
        message: builtins.readFile(source_path("../assets/message.txt"))
      }
    end
  end

entrypoint = nix(do: import_nix(ref("modules/result"), x: 41))

[
  P.nix("default.nix", entrypoint),
  P.nix("modules/result", result),
  P.asset("assets/message.txt", message)
]
