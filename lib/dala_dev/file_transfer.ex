defmodule DalaDev.FileTransfer do
  @moduledoc """
  Transfers files and folders between the dev machine and connected mobile devices.

  Supports push, pull, sync (bidirectional with delete), and ls operations
  across Android devices, iOS simulators, and physical iOS devices.

  ## Folder transfer

  Folders are transferred as atomic tar archives on Android (to preserve
  SELinux context and avoid per-file overhead). On iOS Simulator, `cp -r` is
  used directly. On iOS Physical, `xcrun devicectl` handles directory copies.

  ## Sync

  `sync/3` computes a local<->remote diff based on file sizes and mtimes, then
  transfers only changed files and optionally deletes remote files that don't
  exist locally.

  ## Path conventions

  Relative paths resolve against the app's files directory on device:
  - Android: /data/data/<bundle_id>/files/
  - iOS Simulator: <sim_data>/Documents/
  - iOS Physical: Documents/ (relative to app container)

  Absolute paths (starting with /) are used as-is (rooted Android only).
  """

  alias DalaDev.Discovery.{Android, IOS}
  alias DalaDev.Device
  alias DalaDev.FileTransfer.Platform

  @type transfer_result :: {:ok, String.t()} | {:error, String.t()}
  @type sync_action :: {:push, String.t()} | {:pull, String.t()} | {:delete, String.t()}
  @type sync_result :: {:ok, [sync_action()]} | {:error, String.t()}

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Pushes a local file or directory to connected device(s).

  ## Options

    * `:device` - Target device ID (optional, targets all if omitted)
    * `:on_conflict` - `:overwrite` (default), `:skip`, or `:rename`
    * `:progress` - `true` to print per-file progress (default: `false`)
  """
  @spec push(String.t(), String.t(), keyword()) :: [transfer_result()]
  def push(local_path, remote_path, opts \\ []) do
    device_id = Keyword.get(opts, :device, nil)
    on_conflict = Keyword.get(opts, :on_conflict, :overwrite)
    progress? = Keyword.get(opts, :progress, false)
    devices = discover_devices(device_id)

    if devices == [] do
      [{:error, "No connected devices found."}]
    else
      Enum.map(devices, fn device ->
        label = device.name || device.serial
        prefix = "  #{label}  ->  pushing #{Path.basename(local_path)}..."

        result =
          dispatch_push(device, local_path, remote_path,
            on_conflict: on_conflict,
            progress: progress?
          )

        case result do
          {:ok, msg} -> DalaDev.Output.info("#{prefix} OK #{msg}")
          {:error, reason} -> DalaDev.Output.error("#{prefix} FAIL #{reason}")
        end

        result
      end)
    end
  end

  @doc """
  Pulls a file or directory from a device to the local machine.

  ## Options

    * `:device` - Source device ID (required for multiple devices)
    * `:on_conflict` - `:overwrite` (default), `:skip`, or `:rename`
    * `:progress` - `true` to print per-file progress (default: `false`)
  """
  @spec pull(String.t(), String.t(), keyword()) :: [transfer_result()]
  def pull(remote_path, local_path, opts \\ []) do
    device_id = Keyword.get(opts, :device, nil)
    on_conflict = Keyword.get(opts, :on_conflict, :overwrite)
    progress? = Keyword.get(opts, :progress, false)
    devices = discover_devices(device_id)

    if devices == [] do
      [{:error, "No connected devices found."}]
    else
      Enum.map(devices, fn device ->
        label = device.name || device.serial
        prefix = "  #{label}  <-  pulling #{Path.basename(remote_path)}..."

        result =
          dispatch_pull(device, remote_path, local_path,
            on_conflict: on_conflict,
            progress: progress?
          )

        case result do
          {:ok, msg} -> DalaDev.Output.info("#{prefix} OK #{msg}")
          {:error, reason} -> DalaDev.Output.error("#{prefix} FAIL #{reason}")
        end

        result
      end)
    end
  end

  @doc """
  Synchronizes a local directory with a remote directory on device(s).

  Computes a diff based on file sizes and modification times, then:
  - Pushes files that are new or changed locally
  - Pulls files that are new or changed on device
  - Optionally deletes remote files that don't exist locally

  ## Options

    * `:device` - Target device ID (optional, targets all if omitted)
    * `:delete` - `true` to delete remote files not present locally (default: `false`)
    * `:dry_run` - `true` to print actions without executing (default: `false`)
    * `:progress` - `true` to print per-file progress (default: `false`)
  """
  @spec sync(String.t(), String.t(), keyword()) :: [sync_result()]
  def sync(local_path, remote_path, opts \\ []) do
    device_id = Keyword.get(opts, :device, nil)
    delete? = Keyword.get(opts, :delete, false)
    dry_run? = Keyword.get(opts, :dry_run, false)
    progress? = Keyword.get(opts, :progress, false)
    devices = discover_devices(device_id)

    if devices == [] do
      [{:error, "No connected devices found."}]
    else
      Enum.map(devices, fn device ->
        label = device.name || device.serial

        DalaDev.Output.info(
          "  #{label}  syncing #{Path.basename(local_path)} <-> #{remote_path}..."
        )

        result =
          dispatch_sync(device, local_path, remote_path,
            delete: delete?,
            dry_run: dry_run?,
            progress: progress?
          )

        case result do
          {:ok, actions} ->
            print_sync_summary(actions, dry_run?)
            {:ok, actions}

          {:error, reason} ->
            DalaDev.Output.error("    FAIL: #{reason}")
            {:error, reason}
        end
      end)
    end
  end

  @doc "Lists files in a directory on a device. Returns `{:ok, files}` or `{:error, reason}`."
  @spec ls(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, String.t()}
  def ls(remote_path, opts \\ []) do
    device_id = Keyword.get(opts, :device, nil)
    devices = discover_devices(device_id)

    case devices do
      [] -> {:error, "No connected devices found."}
      [device | _rest] -> dispatch_ls(device, remote_path)
      _ -> {:error, "Multiple devices found. Use --device to specify one."}
    end
  end

  # ── Device dispatch ─────────────────────────────────────────────────────────

  defp discover_devices(nil) do
    (Android.list_devices() ++ IOS.list_devices())
    |> Enum.reject(&(&1.status == :unauthorized))
  end

  defp discover_devices(device_id) do
    case Enum.filter(discover_devices(nil), &Device.match_id?(&1, device_id)) do
      [] ->
        DalaDev.Output.error("No device matched \"#{device_id}\".")
        DalaDev.Output.hint("Run `mix dala.devices` to see available device IDs.")
        []

      matched ->
        matched
    end
  end

  defp dispatch_push(%Device{platform: :android} = device, local, remote, opts) do
    Platform.Android.push(device, local, remote, opts)
  end

  defp dispatch_push(%Device{platform: :ios, type: :simulator} = device, local, remote, opts) do
    Platform.Simulator.push(device, local, remote, opts)
  end

  defp dispatch_push(%Device{platform: :ios, type: :physical} = device, local, remote, opts) do
    Platform.Physical.push(device, local, remote, opts)
  end

  defp dispatch_pull(%Device{platform: :android} = device, remote, local, opts) do
    Platform.Android.pull(device, remote, local, opts)
  end

  defp dispatch_pull(%Device{platform: :ios, type: :simulator} = device, remote, local, opts) do
    Platform.Simulator.pull(device, remote, local, opts)
  end

  defp dispatch_pull(%Device{platform: :ios, type: :physical} = device, remote, local, opts) do
    Platform.Physical.pull(device, remote, local, opts)
  end

  defp dispatch_ls(%Device{platform: :android} = device, remote_path) do
    Platform.Android.ls(device, remote_path)
  end

  defp dispatch_ls(%Device{platform: :ios, type: :simulator} = device, remote_path) do
    Platform.Simulator.ls(device, remote_path)
  end

  defp dispatch_ls(%Device{platform: :ios, type: :physical} = device, remote_path) do
    Platform.Physical.ls(device, remote_path)
  end

  defp dispatch_sync(%Device{platform: :android} = device, local, remote, opts) do
    Platform.Android.sync(device, local, remote, opts)
  end

  defp dispatch_sync(%Device{platform: :ios, type: :simulator} = device, local, remote, opts) do
    Platform.Simulator.sync(device, local, remote, opts)
  end

  defp dispatch_sync(%Device{platform: :ios, type: :physical} = device, local, remote, opts) do
    Platform.Physical.sync(device, local, remote, opts)
  end

  # ── Sync summary helpers ────────────────────────────────────────────────────

  defp print_sync_summary(actions, dry_run?) do
    counts = Enum.frequencies_by(actions, fn {action, _} -> action end)
    push = Map.get(counts, :push, 0)
    pull = Map.get(counts, :pull, 0)
    delete = Map.get(counts, :delete, 0)
    prefix = if dry_run?, do: "[dry-run] ", else: ""
    parts = []
    parts = if push > 0, do: ["#{push} pushed" | parts], else: parts
    parts = if pull > 0, do: ["#{pull} pulled" | parts], else: parts
    parts = if delete > 0, do: ["#{delete} deleted" | parts], else: parts
    summary = if parts == [], do: "already in sync", else: Enum.join(parts, ", ")
    DalaDev.Output.info("    #{prefix}#{summary}")
  end
end
