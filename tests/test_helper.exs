# Initialize a fresh sandbox store before concurrent evaluator tests open it.
case System.cmd(
       "nix",
       ["--extra-experimental-features", "nix-command", "store", "ping", "--json"],
       stderr_to_stdout: true
     ) do
  {_, 0} -> :ok
  {output, status} -> raise "Nix test store initialization failed (#{status}): #{output}"
end

ExUnit.start()
Code.require_file("support.exs", __DIR__)
