defmodule Mix.Tasks.Dala.FileLs do
  use Mix.Task

  @shortdoc "List files in a directory on a connected device"

  @moduledoc """
  Lists files in a directory on a connected mobile device.

  ## Usage

      mix dala.file_ls [remote_path]

  ## Arguments

    * `remote_path` - Path on the device (relative to the app's files directory,
                      or absolute starting with `/`). Defaults to the app root.

  ## Options

    * `--device <id>` - Target device (required when multiple devices are connected)

  ## Examples

      # List files in the app's files directory
      mix dala.file_ls --device emulator-5554

      # List files in a subdirectory
      mix dala.file_ls data --device emulator-5554

      # List files in an absolute path (rooted Android only)
      mix dala.file_ls /sdcard/Download --device emulator-5554
  """

  @switches [
    device: :string
  ]

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])

    {opts, positional, _} = OptionParser.parse(args, switches: @switches)

    remote_path =
      case positional do
        [path] -> path
        [] -> "."
        _ -> Mix.raise("Usage: mix dala.file_ls [remote_path] [--device <id>]")
      end

    device_id = opts[:device]

    case DalaDev.FileTransfer.ls(remote_path, device: device_id) do
      {:ok, files} ->
        DalaDev.Output.info("")
        Enum.each(files, &DalaDev.Output.info("  #{&1}"))
        DalaDev.Output.info("")

      {:error, reason} ->
        Mix.raise(reason)
    end
  end
end
