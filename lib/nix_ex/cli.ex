defmodule NixEx.CLI do
  @usage """
  usage: nix-ex COMMAND [ARGUMENTS]

    convert [SOURCE.exs [DESTINATION]]   Generate Nix (defaults: generate.exs, generated/)
    import SOURCE.nix [FILE.exs]         Convert Nix to editable Elixir
    check [TARGET]                      Evaluate Nix (default: generated/)
      --attr ATTRIBUTE                  Evaluate a particular attribute
      --against ORIGINAL                Compare evaluated JSON values
      --project FILE                    Read settings (default: nix-ex.exs)
      --offline                         Use cached flake inputs
    generate FILE.exs DESTINATION        Generate an explicit project
    demo DESTINATION                    Generate the synthetic demo
    check-demo DESTINATION              Check demo output for drift
    --help                              Show this help

  Elixir source and project settings are trusted executable code.
  Checks do not build or activate a system; unapplied function bodies stay lazy.
  """
  def main(args) do
    case run(args) do
      {:ok, message} ->
        IO.puts(message)

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  def run(["--help"]), do: {:ok, @usage}
  def run(["-h"]), do: {:ok, @usage}

  def run([command, help])
      when command in ["convert", "import", "check"] and help in ["--help", "-h"],
      do: {:ok, @usage}

  def run([command | args]) when command in ["convert", "import", "check"],
    do: NixEx.Workflow.run(command, args)

  def run(["demo", destination]), do: generate(NixEx.Demo.files(), destination)

  def run(["check-demo", destination]) do
    if NixEx.Project.check(NixEx.Demo.files(), destination),
      do: {:ok, "Generated tree matches."},
      else: {:error, "Generated tree differs or is missing."}
  end

  def run(["generate", script, destination]) do
    # Like mix run, scripts are trusted local Elixir programs, with full host access.
    {entries, _binding} = Code.eval_file(script)
    generate(entries, destination)
  rescue
    error -> {:error, Exception.message(error)}
  end

  def run(_), do: {:error, @usage}

  defp generate(entries, destination) do
    :ok = NixEx.Project.write(entries, destination)
    {:ok, "Generated #{Path.expand(destination)}"}
  rescue
    error -> {:error, Exception.message(error)}
  end
end
