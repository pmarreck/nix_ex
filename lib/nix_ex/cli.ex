defmodule NixEx.CLI do
  @usage "usage: nix-ex demo DESTINATION | check-demo DESTINATION | generate FILE.exs DESTINATION | --help"
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
