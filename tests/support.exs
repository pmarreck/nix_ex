defmodule NixEx.TestSupport do
  def tmp! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "nix-ex-test-#{System.unique_integer([:positive, :monotonic])}-#{:os.getpid()}"
      )

    File.mkdir!(dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  def eval!(expr) do
    {out, status} =
      System.cmd(
        "nix-instantiate",
        ["--eval", "--strict", "--json", "--expr", NixEx.Render.render(expr)],
        stderr_to_stdout: true
      )

    if status != 0, do: raise("Nix evaluation failed: #{out}")
    String.trim(out)
  end

  def eval_file(path, args \\ []) do
    {out, status} =
      System.cmd("nix-instantiate", ["--eval", "--strict", "--json", path] ++ args,
        stderr_to_stdout: true
      )

    {String.trim(out), status}
  end
end
