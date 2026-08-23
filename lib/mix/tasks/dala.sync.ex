defmodule Mix.Tasks.Dala.Sync do
  use Mix.Task

  @shortdoc "Sync a local directory with a device directory"

  @moduledoc """
  Synchronizes a local directory with a remote directory on connected device(s).

  Computes a diff based on file sizes and modification times, then:
  - Pushes files that are new or changed locally
  - Pulls files that are new or changed on device
  - Optionally deletes remote files that don't exist locally

  ## Usage

      mix dala.sync <local_path> <remote_path>

  ## Options

    * `--device <id>`   - Target a specific device (default: all devices)
    * `--delete`        - Delete remote files not present locally
    * `--dry-run`       - Print actions without executing
    * `--progress`      - Print per-file progress

  ## Examples

      # Sync fixtures, deleting remote extras
      mix dala.sync priv/fixtures fixtures --device emulator-5554 --delete

      # Dry run to see what would change
      mix dala.sync config config --device emulator-5554 --dry-run

      # Full sync with progress
      mix dala.sync assets assets --device emulator-5554 --delete --progress
  """

  @switches [
    device: :string,
    delete: :boolean,
    dry_run: :boolean,
    progress: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])
    {opts, positional, _} = OptionParser.parse(args, switches: @switches)

    case positional do
      [local_path, remote_path] ->
        unless File.dir?(local_path) do
          Mix.raise("Local path is not a directory: #{local_path}")
        end

        device_id = opts[:device]
        delete? = Keyword.get(opts, :delete, false)
        dry_run? = Keyword.get(opts, :dry_run, false)
        progress? = Keyword.get(opts, :progress, false)
        DalaDev.Output.info("")

        results =
          DalaDev.FileTransfer.sync(local_path, remote_path,
            device: device_id,
            delete: delete?,
            dry_run: dry_run?,
            progress: progress?
          )

        summarize(results)

      _ ->
        Mix.raise(
          "Usage: mix dala.sync <local_path> <remote_path> [--device <id>] [--delete] [--dry-run] [--progress]"
        )
    end
  end

  defp summarize(results) do
    ok = for {:ok, _} <- results, do: true
    err = for {:error, _} <- results, do: true
    DalaDev.Output.info("")

    if length(ok) > 0 do
      DalaDev.Output.success("Synced #{length(ok)} device(s).")
    end

    if length(err) > 0 do
      DalaDev.Output.error("Failed on #{length(err)} device(s).")
    end
  end
end
