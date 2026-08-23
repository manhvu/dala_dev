defmodule DalaDev.DeepLink do
  @moduledoc """
  Opens URLs and deep links on connected devices.

  The device-side counterpart is `Dala.Platform.Linking`; this module is the
  dev-machine side — firing `myapp://product/42` or an https URL at the
  screen you're testing without retyping UDIDs.
  """

  alias DalaDev.Device
  alias DalaDev.Discovery.{Android, IOS}
  alias DalaDev.Utils

  @type result :: {:ok, String.t()} | {:error, String.t()}

  # ── Pure builders (public test seams) ───────────────────────────────────────

  @doc """
  Validates a deep link / URL. Accepts any scheme (`https`, custom app
  schemes like `myapp://`); rejects strings with no scheme since neither
  platform can route them.
  """
  @spec valid_url?(String.t()) :: boolean()
  def valid_url?(url) when is_binary(url) do
    Regex.match?(Utils.compile_regex("^[a-zA-Z][a-zA-Z0-9+.-]*:.+$"), url)
  end

  def valid_url?(_), do: false

  @doc "adb argument list that opens a URL on Android."
  @spec android_open_command(String.t(), String.t()) :: [String.t()]
  def android_open_command(serial, url) do
    ["-s", serial, "shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", url]
  end

  @doc "xcrun argument list that opens a URL on an iOS simulator."
  @spec ios_open_command(String.t(), String.t()) :: [String.t()]
  def ios_open_command(udid, url) do
    ["simctl", "openurl", udid, url]
  end

  # ── Dispatch ────────────────────────────────────────────────────────────────

  @doc """
  Opens `url` on matching devices (all connected by default).
  Returns `{label, result}` per device.

  Options: `:device`, plus test seams `:devices` (explicit device list) and
  `:exec` (command executor override).
  """
  @spec open(String.t(), keyword()) :: [{String.t(), result()}]
  def open(url, opts \\ []) do
    unless valid_url?(url) do
      raise ArgumentError,
            "not a routable URL: #{inspect(url)} — expected a scheme like https:// or myapp://"
    end

    device_id = Keyword.get(opts, :device)

    devices =
      (Keyword.get(opts, :devices) || Android.list_devices() ++ IOS.list_devices())
      |> Enum.reject(&(&1.status == :unauthorized))
      |> filter_by_device(device_id)

    open_devices(devices, url, opts)
  end

  # ── Internals ───────────────────────────────────────────────────────────────

  # Opens the URL on an explicit device list. Public test seam — lets tests
  # inject fake devices instead of running discovery. `opts[:exec]` overrides
  # command execution; commands are tagged `{:adb, args}` / `{:xcrun, args}`.
  @doc false
  @spec open_devices([Device.t()], String.t(), keyword()) :: [{String.t(), result()}]
  def open_devices(devices, url, opts) do
    exec = Keyword.get(opts, :exec, &default_exec/1)

    Enum.map(devices, fn device ->
      {device.name || device.serial, open_on_device(device, url, exec)}
    end)
  end

  defp open_on_device(%Device{platform: :android} = device, url, exec) do
    case exec.({:adb, android_open_command(device.serial, url)}) do
      {:ok, _} -> {:ok, "opened #{url}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp open_on_device(%Device{platform: :ios, type: :simulator} = device, url, exec) do
    case exec.({:xcrun, ios_open_command(device.serial, url)}) do
      {:ok, _} -> {:ok, "opened #{url}"}
      {:error, reason} -> {:error, "simctl openurl failed: #{reason}"}
    end
  end

  defp open_on_device(%Device{platform: :ios}, _url, _exec) do
    {:error, "openurl needs a booted simulator (physical iOS not supported)"}
  end

  defp default_exec({:adb, args}) do
    Utils.run_adb_with_timeout(args)
  end

  defp default_exec({:xcrun, args}) do
    case System.cmd("xcrun", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, _} -> {:error, String.trim(out)}
    end
  end

  defp filter_by_device(devices, nil), do: devices

  defp filter_by_device(devices, id), do: Enum.filter(devices, &Device.match_id?(&1, id))
end
