defmodule NixEx.Workflow do
  @moduledoc "Short local conversion and evaluation workflows; project settings are trusted Elixir."
  alias NixEx.{Migrate, Project}

  def run(command, args) do
    {options, positional, invalid} =
      OptionParser.parse(args,
        strict: [
          project: :string,
          attr: :string,
          against: :string,
          offline: :boolean,
          nixpkgs: :boolean,
          json: :boolean,
          arg: :keep
        ]
      )

    if invalid != [], do: raise(ArgumentError, "unknown options: #{inspect(invalid)}")

    allowed =
      if command == "check",
        do: [:project, :attr, :against, :offline, :nixpkgs, :json, :arg],
        else: if(command == "convert", do: [:project], else: [])

    irrelevant = Enum.uniq(Keyword.keys(options)) -- allowed

    if irrelevant != [],
      do: raise(ArgumentError, "options not valid for #{command}: #{inspect(irrelevant)}")

    settings_path = Keyword.get(options, :project, "nix-ex.exs")

    settings =
      if command == "import",
        do: [],
        else: settings(settings_path, Keyword.has_key?(options, :project))

    perform(command, positional, options, settings)
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp settings(path, required) do
    if required or File.exists?(path) do
      {config, _} = Code.eval_file(path)

      unless Keyword.keyword?(config),
        do: raise(ArgumentError, "project settings must be a keyword list")

      unknown = Keyword.keys(config) -- [:source, :output, :attribute, :inputs, :offline]
      if unknown != [], do: raise(ArgumentError, "unknown project settings: #{inspect(unknown)}")
      Keyword.put(config, :root, Path.dirname(Path.expand(path)))
    else
      []
    end
  end

  defp perform("convert", positional, _options, config) when length(positional) <= 2 do
    root = Keyword.get(config, :root, File.cwd!())

    script =
      Enum.at(positional, 0) || Path.expand(Keyword.get(config, :source, "generate.exs"), root)

    output =
      Enum.at(positional, 1) ||
        Path.expand(
          Keyword.get(config, :output, "generated"),
          Keyword.get(config, :root, Path.dirname(Path.expand(script)))
        )

    {value, _} = Code.eval_file(script)
    entries = if project_entries?(value), do: value, else: [Project.nix("default.nix", value)]
    :ok = Project.write(entries, output)
    {:ok, "Generated #{Path.expand(output)}"}
  end

  defp perform("import", [source | rest], _options, _config) when length(rest) <= 1 do
    source = Path.expand(source)
    output = List.first(rest) || source <> ".exs"
    bytes = source |> Migrate.from_file(root: Path.dirname(source)) |> Migrate.to_elixir()
    :ok = Project.write_file(output, bytes)
    {:ok, "Converted #{source} to #{Path.expand(output)}"}
  end

  defp perform("check", positional, options, config) when length(positional) <= 1 do
    root = Keyword.get(config, :root, File.cwd!())

    target =
      List.first(positional) || Path.expand(Keyword.get(config, :output, "generated"), root)

    attribute = Keyword.get(options, :attr, Keyword.get(config, :attribute))
    against = Keyword.get(options, :against)
    json = Keyword.get(options, :json, false)

    if json and against,
      do: raise(ArgumentError, "--json and --against are separate output modes")

    first = evaluate(target, attribute, options, config, json or against != nil)

    if against do
      second = evaluate(against, attribute, options, config, true)

      if :json.decode(first) != :json.decode(second),
        do: raise(ArgumentError, "Evaluated values differ.")

      {:ok, "Evaluated values match."}
    else
      {:ok, if(json, do: first, else: "Nix evaluation passed: #{Path.expand(target)}")}
    end
  end

  defp perform(_, _, _, _),
    do:
      raise(
        ArgumentError,
        "expected convert [SOURCE [DESTINATION]], import SOURCE [FILE.exs], or check [TARGET]"
      )

  defp project_entries?(%Stream{}), do: true

  defp project_entries?([_ | _] = values),
    do:
      Enum.all?(
        values,
        &match?(%{kind: kind, path: _, value: _, mode: _} when kind in [:nix, :asset], &1)
      )

  defp project_entries?(_), do: false

  defp evaluate(target, attribute, options, config, json) do
    target = Path.expand(target)
    unless File.exists?(target), do: raise(ArgumentError, "missing check target: #{target}")
    flake = File.dir?(target) and File.regular?(Path.join(target, "flake.nix"))

    if flake do
      if Keyword.get(options, :nixpkgs, false) or Keyword.has_key?(options, :arg),
        do: raise(ArgumentError, "--nixpkgs and --arg apply to expression files, not flakes")

      common = [
        "--extra-experimental-features",
        "nix-command flakes",
        "--option",
        "allow-import-from-derivation",
        "false"
      ]

      inputs =
        Enum.flat_map(Keyword.get(config, :inputs, []), fn {name, uri} ->
          ["--override-input", to_string(name), uri]
        end)

      flags =
        ["--no-write-lock-file"] ++
          inputs ++
          if(Keyword.get(options, :offline, Keyword.get(config, :offline, false)),
            do: ["--offline"],
            else: []
          )

      if attribute do
        cmd!("nix", common ++ ["eval", "--json"] ++ flags ++ ["path:#{target}##{attribute}"])
      else
        if json,
          do:
            raise(
              ArgumentError,
              "JSON evaluation or comparison of flakes requires --attr or an attribute in nix-ex.exs"
            )

        cmd!("nix", common ++ ["flake", "check", "--no-build"] ++ flags ++ ["path:#{target}"])
      end
    else
      file = if File.dir?(target), do: Path.join(target, "default.nix"), else: target
      flags = if attribute, do: ["--attr", attribute], else: []
      flags = flags ++ if(json, do: ["--json"], else: [])
      flags = flags ++ arguments(options)

      cmd!(
        "nix-instantiate",
        ["--option", "allow-import-from-derivation", "false", "--eval", "--strict"] ++
          flags ++ [file]
      )
    end
  end

  defp arguments(options) do
    Enum.flat_map(options, fn
      {:nixpkgs, true} ->
        path = System.fetch_env!("NIX_EX_NIXPKGS")
        literal = path |> NixEx.AST.absolute_path() |> NixEx.Render.render() |> String.trim()
        ["--arg", "nixpkgs", literal]

      {:arg, argument} ->
        case String.split(argument, "=", parts: 2) do
          [name, expression] when name != "" and expression != "" ->
            ["--arg", name, expression]

          _ ->
            raise ArgumentError, "--arg expects NAME=EXPRESSION"
        end

      _ ->
        []
    end)
    |> Enum.chunk_every(3)
    |> Enum.reverse()
    |> Enum.uniq_by(&Enum.at(&1, 1))
    |> List.flatten()
  end

  defp cmd!(command, args) do
    directory =
      Path.join(
        System.tmp_dir!(),
        "nix-ex-diagnostics-#{:os.getpid()}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(directory)
    diagnostics = Path.join(directory, "stderr")

    try do
      # Arguments travel as argv, never as interpolated shell source. Keeping
      # stderr separate allows traces and warnings alongside machine-readable JSON.
      {output, status} =
        System.cmd(
          "bash",
          [
            "-c",
            ~S(err=$1; shift; exec "$@" 2>"$err"),
            "nix-ex-check",
            diagnostics,
            command | args
          ],
          stderr_to_stdout: true
        )

      if status != 0,
        do: raise(ArgumentError, "Nix check failed:\n#{File.read!(diagnostics)}#{output}")

      String.trim(output)
    after
      File.rm_rf!(directory)
    end
  end
end
