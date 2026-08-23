defmodule Mix.Tasks.Dala.PushFile do
  use Mix.Task

  @shortdoc "Push a file or directory to connected devices"

  @moduledoc """
  Transfers a local file or directory to connected mobile devices.

  ## Usage

      mix dala.push_file <local_path> <remote_path>

  ## Options

    * `--device <id>`        - Target a specific device (default: all devices)
    * `--on_conflict <mode>` - Conflict resolution: overwrite (default), skip, or rename
    * `--progress`           - Print per-file progress for directories

  ## Examples

      mix dala.push_file config/dev.exs config/dev.exs
      mix dala.push_file assets/data.json data.json --device emulator-5554
      mix dala.push_file priv/fixtures fixtures --progress
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
      [local_path, remote_path] ->
        on_conflict = parse_conflict(Keyword.get(opts, :on_conflict, "overwrite"))
        device_id = opts[:device]
        progress? = Keyword.get(opts, :progress, false)
        DalaDev.Output.info("")

        results =
          DalaDev.FileTransfer.push(local_path, remote_path,
            device: device_id,
            on_conflict: on_conflict,
            progress: progress?
          )

        summarize(results)

      _ ->
        Mix.raise(
          "Usage: mix dala.push_file <local_path> <remote_path> [--device <id>] [--on_conflict overwrite|skip|rename] [--progress]"
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
      DalaDev.Output.success("Transferred to #{length(ok)} device(s).")
    end

    if length(err) > 0 do
      DalaDev.Output.error("Failed on #{length(err)} device(s).")
    end
  end
end
