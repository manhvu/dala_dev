defmodule DalaDev.DeviceShell do
  @moduledoc """
  Builds commands for shelling into an app's sandbox on a device.

  The recurring chore this removes: on Android, poking around the app's
  private data dir needs `adb shell run-as <bundle>`; on iOS Simulator the
  app container is a host directory you find via `simctl get_app_container`.
  Both are easy to forget and annoying to retype — especially with a
  specific UDID/serial.

  Pure command builders here are public test seams; the Mix task resolves
  the device and either prints or executes the result.
  """

  alias DalaDev.Device
  alias DalaDev.Discovery.{Android, IOS}

  @type target ::
          {:android, String.t()} | {:ios_simulator, String.t()} | {:ios_physical, String.t()}

  @type command ::
          {:shell, String.t()} | {:dir, String.t()} | {:exec, String.t()} | :unsupported

  # ── Resolution ──────────────────────────────────────────────────────────────

  @doc """
  Resolves `device_id` (or the first connected device when nil) into a shell
  target. Returns `{:ok, target, label}` or `{:error, reason}`.

  `lister/0` overrides discovery (test seam — same pattern as
  `NativeBuild.narrow_platforms_for_device/3`).
  """
  @spec resolve_target(String.t() | nil, (-> [Device.t()])) ::
          {:ok, target(), String.t()} | {:error, String.t()}
  def resolve_target(device_id, lister \\ &default_lister/0) do
    devices =
      lister.()
      |> Enum.reject(&(&1.status == :unauthorized))
      |> filter_by_device(device_id)

    case devices do
      [%Device{} = device | _] ->
        target =
          case {device.platform, device.type} do
            {:android, _} -> {:android, device.serial}
            {:ios, :simulator} -> {:ios_simulator, device.serial}
            {:ios, _} -> {:ios_physical, device.serial}
          end

        {:ok, target, device.name || device.serial}

      [] ->
        if device_id do
          {:error, "no device matched \"#{device_id}\""}
        else
          {:error, "no connected devices found"}
        end
    end
  end

  # ── Command builders (public test seams) ────────────────────────────────────

  @doc """
  Command that drops into the app's private data area:

    * Android → interactive `run-as` shell
    * iOS simulator → prints the app's data container path (`{:dir, cmd}`)
    * iOS physical → `:unsupported` (no public sandbox exec)
  """
  @spec open_command(target(), String.t()) :: command()
  def open_command({:android, serial}, bundle) do
    {:shell, "adb -s #{serial} shell run-as #{bundle}"}
  end

  def open_command({:ios_simulator, udid}, bundle) do
    {:dir, "xcrun simctl get_app_container #{udid} #{bundle} data"}
  end

  def open_command({:ios_physical, _udid}, _bundle) do
    :unsupported
  end

  @doc """
  One-shot command that runs inside the app's data area:

    * Android → `adb ... run-as <bundle> -c '<script>'`
    * iOS simulator → resolves the container then runs the script from it
    * iOS physical → `:unsupported`
  """
  @spec exec_command(target(), String.t(), String.t()) :: command()
  def exec_command(target, bundle, script)

  def exec_command({:android, serial}, bundle, script) do
    {:exec, "adb -s #{serial} shell run-as #{bundle} -c #{single_quote(script)}"}
  end

  def exec_command({:ios_simulator, udid}, bundle, script) do
    container_cmd = "xcrun simctl get_app_container #{udid} #{bundle} data"
    {:exec, "cd \"$(#{container_cmd})\" && sh -c #{single_quote(script)}"}
  end

  def exec_command({:ios_physical, _udid}, _bundle, _script), do: :unsupported

  # ── Execution ───────────────────────────────────────────────────────────────

  @doc """
  Runs a resolved `{:exec, cmd}` plan through the shell, streaming output.
  Returns the exit status. Only ever called with locally-built commands.
  """
  @spec run(String.t()) :: non_neg_integer()
  def run(command) do
    System.cmd("sh", ["-c", command], into: IO.stream(:stdio, :line))
    |> elem(1)
  end

  # ── Internals ───────────────────────────────────────────────────────────────

  # Single-quote for POSIX sh: close the quote, insert an escaped literal
  # single quote, reopen.
  defp single_quote(script) do
    "'" <> String.replace(script, "'", "'\\''") <> "'"
  end

  defp filter_by_device(devices, nil), do: devices

  defp filter_by_device(devices, id), do: Enum.filter(devices, &Device.match_id?(&1, id))

  defp default_lister, do: Android.list_devices() ++ IOS.list_devices()
end
