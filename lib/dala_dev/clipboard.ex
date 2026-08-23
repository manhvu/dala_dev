defmodule DalaDev.DeviceClipboard do
  @moduledoc """
  Reads and writes the device clipboard from the dev machine.

  Primary use: pasting long strings (tokens, fixtures, URLs) into a device
  text field during manual testing instead of typing them on a virtual
  keyboard. The app-side counterpart is `Dala.Platform.Clipboard`.

  Platform support:

    * iOS Simulator — full read/write via `xcrun simctl pbpaste/pbcopy`
      (the sim shares the host clipboard plumbing)
    * Android — not supported by adb on modern Android (clipboard access is
      blocked for background processes); returns a clear error with the
      `adb shell input text` alternative
    * iOS physical — not supported from CLI
  """

  alias DalaDev.Device
  alias DalaDev.Discovery.{Android, IOS}

  @type result :: {:ok, String.t()} | {:error, String.t()}

  # ── Pure builders (public test seams) ───────────────────────────────────────

  @doc "xcrun argument list that prints an iOS simulator's clipboard."
  @spec ios_get_command(String.t()) :: [String.t()]
  def ios_get_command(udid), do: ["simctl", "pbpaste", udid]

  @doc """
  xcrun argument list that sets an iOS simulator's clipboard to `text`.
  Text is passed via stdin (the `pbcopy` form reads stdin), so this returns
  the args plus a marker for the dispatcher.
  """
  @spec ios_put_command(String.t(), String.t()) :: [String.t()]
  def ios_put_command(udid, _text), do: ["simctl", "pbcopy", udid]

  # ── Dispatch ────────────────────────────────────────────────────────────────

  @doc """
  Reads the clipboard of `device_id` (or the first connected device).

  Test seams: `opts[:devices]` overrides discovery, `opts[:exec]` overrides
  the xcrun call (receives `(args, input)`, returns `{output, code}`).
  """
  @spec get(String.t() | nil, keyword()) :: result()
  def get(device_id, opts \\ []) do
    case resolve(device_id, opts) do
      {:ok, %Device{platform: :ios, type: :simulator, serial: udid}} ->
        exec = Keyword.get(opts, :exec, &default_exec/2)

        {out, code} = exec.(ios_get_command(udid), nil)

        if code == 0,
          do: {:ok, out},
          else: {:error, "simctl pbpaste failed"}

      {:ok, %Device{platform: :android}} ->
        {:error,
         "adb cannot read the Android clipboard — use `adb shell input text \"...\"` into the focused field"}

      {:ok, %Device{platform: :ios}} ->
        {:error, "physical iOS clipboard is not reachable from the CLI"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sets the clipboard of `device_id` (or the first connected device) to `text`.
  Same test seams as `get/2`.
  """
  @spec put(String.t(), String.t() | nil, keyword()) :: result()
  def put(text, device_id, opts \\ []) do
    case resolve(device_id, opts) do
      {:ok, %Device{platform: :ios, type: :simulator, serial: udid}} ->
        exec = Keyword.get(opts, :exec, &default_exec/2)

        {_out, code} = exec.(ios_put_command(udid, text), text)

        if code == 0,
          do: {:ok, "clipboard set"},
          else: {:error, "simctl pbcopy failed"}

      {:ok, %Device{platform: :android}} ->
        {:error,
         "adb cannot set the Android clipboard — focus the field and use `adb shell input text \"...\"`"}

      {:ok, %Device{platform: :ios}} ->
        {:error, "physical iOS clipboard is not reachable from the CLI"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Internals ───────────────────────────────────────────────────────────────

  defp default_exec(args, nil), do: System.cmd("xcrun", args, stderr_to_stdout: true)

  defp default_exec(args, input),
    do: System.cmd("xcrun", args, stderr_to_stdout: true, input: input)

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
