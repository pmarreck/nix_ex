defmodule NixEx.Project do
  @moduledoc "Plan a complete output tree, then publish a fresh directory. Changed destinations are never overwritten."
  alias NixEx.Render

  def nix(path, expression), do: %{path: path, kind: :nix, value: expression, mode: 0o644}

  def asset(path, bytes, opts \\ []),
    do: %{path: path, kind: :asset, value: bytes, mode: Keyword.get(opts, :mode, 0o644)}

  def identity!(path) when is_binary(path) do
    if path == "" or Path.type(path) != :relative or
         String.contains?(path, ["\\", <<0>>, "\n", "\r"]) or
         Enum.any?(String.split(path, "/"), &(&1 in ["", ".", ".."])) do
      raise ArgumentError, "invalid project-relative output identity: #{inspect(path)}"
    end

    path
  end

  def identity!(path), do: raise(ArgumentError, "invalid output identity: #{inspect(path)}")

  def destination!(path) do
    expanded = Path.expand(path)

    if expanded in ["/", System.user_home!()],
      do: raise(ArgumentError, "refusing broad destination: #{expanded}")

    expanded
  end

  def plan(entries) do
    entries = Enum.to_list(entries)
    names = Enum.map(entries, &identity!(&1.path))

    if length(Enum.uniq(names)) != length(names),
      do: raise(ArgumentError, "duplicate project output")

    outputs = MapSet.new(names)

    for name <- names do
      ancestors = name |> Path.split() |> Enum.drop(-1) |> prefixes()

      if Enum.any?(ancestors, &MapSet.member?(outputs, &1)),
        do: raise(ArgumentError, "file/directory output collision: #{name}")
    end

    entries
    |> Enum.map(fn entry ->
      unless entry.mode in [0o644, 0o755],
        do: raise(ArgumentError, "asset mode must be 0644 or 0755")

      bytes =
        case entry.kind do
          :nix -> Render.render(entry.value, file: entry.path, outputs: outputs)
          :asset when is_binary(entry.value) -> entry.value
          _ -> raise ArgumentError, "invalid output entry: #{inspect(entry.path)}"
        end

      {entry.path, bytes, entry.mode}
    end)
    |> Enum.sort()
  end

  def write(entries, destination) do
    planned = plan(entries)
    destination = destination!(destination)
    parent = Path.dirname(destination)
    no_symlinks!(parent)
    unless File.dir?(parent), do: raise(ArgumentError, "destination parent must exist: #{parent}")
    lock = destination <> ".nix-ex-lock"

    case File.mkdir(lock) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, "cannot lock destination: #{reason}"
    end

    try do
      case File.lstat(destination) do
        {:ok, %{type: :directory}} ->
          unless identical?(planned, destination),
            do:
              raise(
                ArgumentError,
                "destination exists and differs; generate into a fresh directory"
              )

          :ok

        {:ok, _} ->
          raise ArgumentError, "destination exists and is not a plain directory"

        {:error, :enoent} ->
          publish(planned, destination, lock)

        {:error, reason} ->
          raise File.Error, reason: reason, action: "inspect", path: destination
      end
    after
      File.rm_rf!(lock)
    end
  end

  def check(entries, destination), do: identical?(plan(entries), destination!(destination))

  def write_file(path, bytes) when is_binary(bytes) do
    path = destination!(path)
    no_symlinks!(Path.dirname(path))

    case File.write(path, bytes, [:exclusive]) do
      :ok ->
        :ok

      {:error, :eexist} ->
        unless match?({:ok, %{type: :regular}}, File.lstat(path)) and File.read!(path) == bytes,
          do:
            raise(
              ArgumentError,
              "destination exists and differs or is not a regular file: #{path}"
            )

        :ok

      {:error, reason} ->
        raise File.Error, reason: reason, action: "write", path: path
    end
  end

  defp publish(planned, destination, lock) do
    staging = Path.join(lock, "tree")
    File.mkdir!(staging)

    for {name, bytes, mode} <- planned do
      path = Path.join(staging, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes, [:exclusive])
      File.chmod!(path, mode)
    end

    # Cooperating writers share the lock. Existing trees are never replaced.
    if File.exists?(destination),
      do: raise(ArgumentError, "destination appeared during generation")

    File.rename!(staging, destination)
    :ok
  end

  defp identical?(planned, destination) do
    expected = Enum.map(planned, &elem(&1, 0))

    matching_tree?(destination, expected) and
      Enum.all?(planned, fn {name, bytes, mode} ->
        path = Path.join(destination, name)

        case {File.read(path), File.stat(path)} do
          {{:ok, ^bytes}, {:ok, stat}} -> Bitwise.band(stat.mode, 0o777) == mode
          _ -> false
        end
      end)
  end

  defp matching_tree?(root, expected) do
    children = Enum.group_by(expected, fn path -> hd(String.split(path, "/")) end)

    with {:ok, %{type: :directory}} <- File.lstat(root),
         {:ok, names} <- File.ls(root),
         true <- Enum.sort(names) == Enum.sort(Map.keys(children)) do
      Enum.all?(children, fn {name, paths} ->
        path = Path.join(root, name)

        if paths == [name] do
          match?({:ok, %{type: :regular}}, File.lstat(path))
        else
          tails = Enum.map(paths, &String.replace_prefix(&1, name <> "/", ""))
          matching_tree?(path, tails)
        end
      end)
    else
      _ -> false
    end
  end

  defp no_symlinks!(path) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} -> raise ArgumentError, "symlink destination ancestor: #{path}"
      _ -> :ok
    end

    parent = Path.dirname(path)
    if parent != path, do: no_symlinks!(parent)
  end

  defp prefixes(parts), do: Enum.scan(parts, &Path.join(&2, &1))
end
