defmodule Mix.Tasks.Dala.WatchStop do
  use Mix.Task

  @shortdoc "Stop a running mix dala.watch process"

  @moduledoc """
  Stops a running `mix dala.watch` process.

      mix dala.watch_stop

  Reads the PID written by `mix dala.watch` and sends SIGTERM.

  ## Under the hood

      pid = File.read!("_build/dala_watch.pid") |> String.trim()
      System.cmd("kill", [pid])   # SIGTERM
      File.rm("_build/dala_watch.pid")

  Equivalent to running `kill $(cat _build/dala_watch.pid)` in a terminal.
  """

  @impl Mix.Task
  def run(_args) do
    DalaDev.Output.configure([])
    pid_file = Mix.Tasks.Dala.Watch.pid_file()

    case File.read(pid_file) do
      {:ok, contents} ->
        pid = String.trim(contents)

        case System.cmd("kill", [pid], stderr_to_stdout: true) do
          {_, 0} ->
            File.rm(pid_file)
            DalaDev.Output.success("dala.watch stopped (pid #{pid})")

          {out, _} ->
            File.rm(pid_file)

            DalaDev.Output.warn(
              "kill failed (process may have already exited): #{String.trim(out)}"
            )
        end

      {:error, _} ->
        DalaDev.Output.warn("dala.watch is not running (no PID file found)")
    end
  end
end
