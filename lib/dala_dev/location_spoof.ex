defmodule DalaDev.LocationSpoof do
  @moduledoc """
  Spoofs the device location from the dev machine.

  Useful when testing `Dala.Platform.Location` without physically moving:
  pin the device to a specific café, a different hemisphere, or the exact
  geofence boundary.

  Platform support:

    * Android emulator — `adb emu geo fix` (physical devices need a mock
      location provider app, which is out of scope)
    * iOS Simulator — `xcrun simctl location ... set`
  """

  alias DalaDev.Device
  alias DalaDev.Discovery.{Android, IOS}

  @type result :: {:ok, String.t()} | {:error, String.t()}

  # ── Pure builders / parsers (public test seams) ─────────────────────────────

  @doc """
  Parses `"lat,lng"` (or with spaces, or `"lat lng"`) into floats.
  Returns `{:ok, lat, lng}` or `{:error, reason}`. Validates ranges
  (|lat| <= 90, |lng| <= 180).
  """
  @spec parse_coords(String.t()) :: {:ok, float(), float()} | {:error, String.t()}
  def parse_coords(input) when is_binary(input) do
    parts =
      input
      |> String.split(Regex.compile!("[,\\s]+"), trim: true)

    with [lat_s, lng_s] <- parts,
         {lat, ""} <- Float.parse(lat_s),
         {lng, ""} <- Float.parse(lng_s),
         :ok <- check_range(lat, lng) do
      {:ok, lat, lng}
    else
      {:error, _} = err -> err
      {_, _rest} -> {:error, "coordinates must be numeric: #{inspect(input)}"}
      _ -> {:error, "expected \"<lat>,<lng>\" — got #{inspect(input)}"}
    end
  end

  def parse_coords(other), do: {:error, "expected \"<lat>,<lng>\" — got #{inspect(other)}"}

  defp check_range(lat, lng) when abs(lat) <= 90 and abs(lng) <= 180, do: :ok

  defp check_range(_lat, _lng), do: {:error, "latitude must be within ±90, longitude within ±180"}

  # NOTE: adb's geo fix takes LONGITUDE first, then latitude.
  @doc "adb argument list that sets the Android emulator's location."
  @spec android_set_command(String.t(), float(), float()) :: [String.t()]
  def android_set_command(serial, lat, lng) do
    ["-s", serial, "emu", "geo", "fix", to_string(lng), to_string(lat)]
  end

  @doc "xcrun argument list that sets an iOS simulator's location."
  @spec ios_set_command(String.t(), float(), float()) :: [String.t()]
  def ios_set_command(udid, lat, lng) do
    ["simctl", "location", udid, "set", "#{lat},#{lng}"]
  end

  @doc "xcrun argument list that clears a simulator's spoofed location."
  @spec ios_clear_command(String.t()) :: [String.t()]
  def ios_clear_command(udid), do: ["simctl", "location", udid, "clear"]

  # ── Dispatch ────────────────────────────────────────────────────────────────

  @doc """
  Sets the location on one device (`device_id` nil = first connected).

  Test seams: `opts[:devices]` overrides discovery; `opts[:exec]` overrides
  command execution — receives tagged `{:adb, args}` / `{:xcrun, args}` and
  returns `{:ok, out}` or `{:error, out}`.
  """
  @spec set(float(), float(), String.t() | nil, keyword()) :: result()
  def set(lat, lng, device_id, opts \\ []) do
    exec = Keyword.get(opts, :exec, &default_exec/1)

    case resolve(device_id, opts) do
      {:ok, %Device{platform: :android, type: type} = device} ->
        if type == :emulator do
          case exec.({:adb, android_set_command(device.serial, lat, lng)}) do
            {:ok, _} ->
              {:ok, "#{device.name || device.serial} → #{format(lat, lng)}"}

            {:error, reason} ->
              {:error, "geo fix failed: #{inspect(reason)}"}
          end
        else
          {:error,
           "location spoofing works on emulators only — physical Android needs a mock-location app"}
        end

      {:ok, %Device{platform: :ios, type: :simulator} = device} ->
        case exec.({:xcrun, ios_set_command(device.serial, lat, lng)}) do
          {:ok, _} ->
            {:ok, "#{device.name || device.serial} → #{format(lat, lng)}"}

          {:error, out} ->
            {:error, "simctl location failed: #{String.trim(out || "")}"}
        end

      {:ok, %Device{platform: :ios}} ->
        {:error, "physical iOS needs Xcode (Features → Location) or gpx — not supported via CLI"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Internals ───────────────────────────────────────────────────────────────

  @doc """
  Clears any spoofed location on `device_id` (or the first connected device).
  """
  @spec clear(String.t() | nil, keyword()) :: result()
  def clear(device_id, opts \\ []) do
    exec = Keyword.get(opts, :exec, &default_exec/1)

    case resolve(device_id, opts) do
      {:ok, %Device{platform: :ios, type: :simulator} = device} ->
        case exec.({:xcrun, ios_clear_command(device.serial)}) do
          {:ok, _} ->
            {:ok, "location spoof cleared"}

          {:error, out} ->
            {:error, "simctl location clear failed: #{String.trim(out || "")}"}
        end

      {:ok, %Device{}} ->
        {:error, "clear is iOS-Simulator-only (Android emulators reset on reboot)"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format(lat, lng), do: "#{lat},#{lng}"

  # Executes a tagged command, normalizing both tool outputs to
  # `{:ok, output}` / `{:error, output_or_reason}`.
  defp default_exec({:adb, args}) do
    DalaDev.Utils.run_adb_with_timeout(args)
  end

  defp default_exec({:xcrun, args}) do
    case System.cmd("xcrun", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, _} -> {:error, String.trim(out)}
    end
  end

  defp resolve(device_id, opts) do
    all = Keyword.get(opts, :devices) || Android.list_devices() ++ IOS.list_devices()

    case device_id do
      nil ->
        case all do
          [%Device{} = device | _] -> {:ok, device}
          [] -> {:error, "no connected devices found"}
        end

      _ ->
        case Enum.find(all, &Device.match_id?(&1, device_id)) do
          nil -> {:error, "no device matched \"#{device_id}\""}
          device -> {:ok, device}
        end
    end
  end
end
