defmodule Mix.Tasks.Dala.PullFile do
  use Mix.Task

  @shortdoc "Pull a file or directory from a connected device"

  @moduledoc """
  Transfers a file or directory from a connected mobile device to the local machine.

  ## Usage

      mix dala.pull_file <remote_path> <local_path>

  ## Options

    * `--device <id>`        - Source device (required when multiple devices are connected)
    * `--on_conflict <mode>` - Conflict resolution: overwrite (default), skip, or rename
    * `--progress`           - Print per-file progress for directories

  ## Examples

      mix dala.pull_file data/backup.json ./backup.json --device emulator-5554
      mix dala.pull_file logs ./device_logs --device emulator-5554 --progress
  """

  @switches [
    device: :string,
    on_conflict: :string,
    progress: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])
    {opts, positional, _} = OptionParser.parse(args, switches: @switches)

    case positional do
      [remote_path, local_path] ->
        on_conflict = parse_conflict(Keyword.get(opts, :on_conflict, "overwrite"))
        device_id = opts[:device]
        progress? = Keyword.get(opts, :progress, false)
        DalaDev.Output.info("")

        results =
          DalaDev.FileTransfer.pull(remote_path, local_path,
            device: device_id,
            on_conflict: on_conflict,
            progress: progress?
          )

        summarize(results)

      _ ->
        Mix.raise(
          "Usage: mix dala.pull_file <remote_path> <local_path> [--device <id>] [--on_conflict overwrite|skip|rename] [--progress]"
        )
    end
  end

  defp parse_conflict("overwrite"), do: :overwrite
  defp parse_conflict("skip"), do: :skip
  defp parse_conflict("rename"), do: :rename

  defp parse_conflict(other),
    do: Mix.raise("Invalid on_conflict mode: #{other}. Use overwrite, skip, or rename.")

  defp summarize(results) do
    ok = for {:ok, _} <- results, do: true
    err = for {:error, _} <- results, do: true
    DalaDev.Output.info("")

    if length(ok) > 0 do
      DalaDev.Output.success("Transferred from #{length(ok)} device(s).")
    end

    if length(err) > 0 do
      DalaDev.Output.error("Failed on #{length(err)} device(s).")
    end
  end
end
