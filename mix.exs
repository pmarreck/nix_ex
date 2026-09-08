defmodule NixEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :nix_ex,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [],
      test_paths: ["tests/unit", "tests/integration"],
      escript: [main_module: NixEx.CLI]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]
end
