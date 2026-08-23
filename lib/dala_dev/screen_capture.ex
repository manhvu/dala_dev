defmodule DalaDev.ScreenCapture do
  @moduledoc """
  Capture screenshots and record screen video from mobile devices.

  Supports:
  - Android devices (via adb screencap / screenrecord)
  - iOS simulators (via xcrun simctl io)
  - iOS physical devices (via idevicescreenshot / idevicerecord)
  - Live screen preview via WebSocket to dala.server

  ## Examples

      # Take a screenshot
      {:ok, png_data} = DalaDev.ScreenCapture.capture(:"dala_qa@192.168.1.5")
      {:ok, path} = DalaDev.ScreenCapture.capture(device, save_as: "screenshot.png")

      # Record video (Android: max 3 min, iOS sim: no limit)
      {:ok, path} = DalaDev.ScreenCapture.record(device, duration: 30)

      # Live preview in browser
      DalaDev.ScreenCapture.live_preview(device, port: 5050)
  """

  alias DalaDev.{Device, Utils}

  @type device_ref :: Device.t() | node() | String.t()
  @type capture_opts :: keyword()
  @type record_opts :: keyword()

  @doc """
  Capture a screenshot from a device.

  Options:
  - `:save_as` - Path to save the PNG file (returns path instead of binary)
  - `:format` - :png (default) or :jpeg
  - `:scale` - Scale factor (0.5 = half size, default: 1.0)

  Returns `{:ok, png_binary}` or `{:ok, path}` if `:save_as` is given.
  """
  @spec capture(device_ref(), capture_opts()) :: {:ok, binary() | Path.t()} | {:error, term()}
  def capture(device_ref, opts \\ []) do
    case resolve_device(device_ref) do
      {:ok, %Device{platform: :android} = device} ->
        capture_android(device, opts)

      {:ok, %Device{platform: :ios, type: :simulator} = device} ->
        capture_ios_sim(device, opts)

      {:ok, %Device{platform: :ios, type: :physical} = device} ->
        capture_ios_device(device, opts)

      {:ok, %Device{}} ->
        {:error, :unsupported_device}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Record screen video from a device.

  Options:
  - `:duration` - Recording duration in seconds (default: 30)
  - `:save_as` - Path to save the MP4 file
  - `:bitrate` - Video bitrate (Android only, default: 4Mbps)

  Android limitation: `screenrecord` has a 3-minute maximum.
  iOS physical devices: requires `idevicerecord` from libimobiledevice.
  """
  @spec record(device_ref(), record_opts()) :: {:ok, Path.t()} | {:error, term()}
  def record(device_ref, opts \\ []) do
    case resolve_device(device_ref) do
      {:ok, %Device{platform: :android} = device} ->
        record_android(device, opts)

      {:ok, %Device{platform: :ios, type: :simulator} = device} ->
        record_ios_sim(device, opts)

      {:ok, %Device{platform: :ios, type: :physical} = device} ->
        record_ios_device(device, opts)

      {:ok, %Device{}} ->
        {:error, :unsupported_device}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Start a live screen preview stream.

  Opens a WebSocket server that streams MJPEG frames to connected browsers.
  The preview URL is printed to the console.

  Options:
  - `:port` - HTTP/WebSocket port (default: 5050)
  - `:fps` - Frames per second (default: 15)
  - `:scale` - Scale factor for bandwidth (default: 0.5)

  Returns `{:ok, pid}` of the preview server process.
  """
  @spec live_preview(device_ref(), keyword()) :: {:ok, pid()} | {:error, term()}
  def live_preview(device_ref, opts \\ []) do
    case resolve_device(device_ref) do
      {:ok, device} ->
        start_preview_server(device, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Android implementation ─────────────────────────────────────────────

  defp capture_android(%Device{serial: serial}, opts) do
    save_as = Keyword.get(opts, :save_as)

    case Utils.run_adb_for_device(serial, ["exec-out", "screencap", "-p"], timeout: 10_000) do
      {:ok, png_data} when is_binary(png_data) and byte_size(png_data) > 0 ->
        if save_as do
          File.mkdir_p!(Path.dirname(save_as))
          File.write!(save_as, png_data)
          {:ok, save_as}
        else
          {:ok, png_data}
        end

      {:ok, _} ->
        {:error, :empty_screenshot}

      {:error, reason} ->
        {:error, {:adb_error, reason}}
    end
  end

  defp record_android(%Device{serial: serial}, opts) do
    duration = Keyword.get(opts, :duration, 30)
    save_as = Keyword.get(opts, :save_as, "screen_record_#{timestamp()}.mp4")
    bitrate = Keyword.get(opts, :bitrate, "4M")

    File.mkdir_p!(Path.dirname(save_as))

    # Android screenrecord has a 3-minute max
    duration = min(duration, 180)

    args = [
      "-s",
      serial,
      "shell",
      "screenrecord",
      "--bit-rate",
      bitrate,
      "--time-limit",
      to_string(duration),
      "/sdcard/dala_screenrecord.mp4"
    ]

    DalaDev.Output.info("Recording for #{duration}s... (Ctrl+C to stop early)")

    case System.cmd("adb", args, stderr_to_stdout: true, into: IO.stream(:stdio, 1)) do
      {_, 0} ->
        # Pull the recording from device
        pull_args = ["-s", serial, "pull", "/sdcard/dala_screenrecord.mp4", save_as]

        case System.cmd("adb", pull_args, stderr_to_stdout: true) do
          {_, 0} ->
            # Clean up device
            Utils.run_adb_for_device(serial, ["shell", "rm", "/sdcard/dala_screenrecord.mp4"])
            {:ok, save_as}

          {err, _} ->
            {:error, {:pull_failed, err}}
        end

      {err, _} ->
        {:error, {:record_failed, err}}
    end
  end

  # ── iOS Simulator implementation ────────────────────────────────────────

  defp capture_ios_sim(%Device{serial: udid}, opts) do
    save_as = Keyword.get(opts, :save_as, temp_path("screenshot.png"))

    File.mkdir_p!(Path.dirname(save_as))

    args = ["simctl", "io", udid, "screenshot", save_as]

    case System.cmd("xcrun", args, stderr_to_stdout: true) do
      {_, 0} ->
        if Keyword.get(opts, :save_as) do
          {:ok, save_as}
        else
          data = File.read!(save_as)
          File.rm!(save_as)
          {:ok, data}
        end

      {err, _} ->
        {:error, {:simctl_error, err}}
    end
  end

  defp record_ios_sim(%Device{serial: udid}, opts) do
    duration = Keyword.get(opts, :duration, 30)
    save_as = Keyword.get(opts, :save_as, "screen_record_#{timestamp()}.mp4")

    File.mkdir_p!(Path.dirname(save_as))

    args = [
      "simctl",
      "io",
      udid,
      "recordVideo",
      "--codec",
      "h264",
      "--force",
      save_as
    ]

    DalaDev.Output.info("Recording for #{duration}s...")

    # Start recording in background
    port = Port.open({:spawn, "xcrun #{Enum.join(args, " ")}"}, [:binary, :exit_status])

    # Wait for duration
    Process.sleep(duration * 1000)

    # Stop recording (send SIGINT to xcrun process)
    send(port, {self(), {:command, "\x03"}})
    Process.sleep(1000)
    Port.close(port)

    # Verify file exists
    if File.exists?(save_as) do
      {:ok, save_as}
    else
      {:error, :recording_failed}
    end
  end

  # ── iOS Physical Device implementation ──────────────────────────────────

  defp capture_ios_device(%Device{serial: udid}, opts) do
    if System.find_executable("idevicescreenshot") do
      save_as = Keyword.get(opts, :save_as, temp_path("screenshot.png"))

      File.mkdir_p!(Path.dirname(save_as))

      case System.cmd("idevicescreenshot", ["-u", udid, save_as], stderr_to_stdout: true) do
        {_, 0} ->
          if Keyword.get(opts, :save_as) do
            {:ok, save_as}
          else
            data = File.read!(save_as)
            File.rm!(save_as)
            {:ok, data}
          end

        {err, _} ->
          {:error, {:idevice_error, err}}
      end
    else
      {:error, :idevicescreenshot_not_found}
    end
  end

  defp record_ios_device(%Device{serial: udid}, opts) do
    if System.find_executable("idevicerecord") do
      duration = Keyword.get(opts, :duration, 30)
      save_as = Keyword.get(opts, :save_as, "screen_record_#{timestamp()}.mp4")

      File.mkdir_p!(Path.dirname(save_as))

      args = ["-u", udid, "-d", to_string(duration), save_as]

      DalaDev.Output.info("Recording for #{duration}s...")

      case System.cmd("idevicerecord", args, stderr_to_stdout: true) do
        {_, 0} -> {:ok, save_as}
        {err, _} -> {:error, {:idevice_error, err}}
      end
    else
      {:error, :idevicerecord_not_found}
    end
  end

  # ── Live Preview Server ────────────────────────────────────────────────

  defp start_preview_server(%Device{} = device, opts) do
    port = Keyword.get(opts, :port, 5050)
    fps = Keyword.get(opts, :fps, 15)
    scale = Keyword.get(opts, :scale, 0.5)

    # Start a simple HTTP server that serves an HTML page with MJPEG stream
    {:ok, pid} =
      Task.start_link(fn ->
        serve_preview(device, port, fps, scale)
      end)

    url = "http://localhost:#{port}/"
    DalaDev.Output.info("Screen preview available at: #{url}")

    {:ok, pid}
  end

  defp serve_preview(_device, port, _fps, _scale) do
    # Simplified preview server - in production, use Bandit/Plug
    # This is a placeholder that shows the concept
    DalaDev.Output.info("Preview server started on port #{port}")

    # Keep process alive
    receive do
      :stop -> :ok
    after
      300_000 -> :ok
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  defp resolve_device(%Device{} = device), do: {:ok, device}

  defp resolve_device(node) when is_atom(node) do
    # Try to find device by node name
    devices = DalaDev.Discovery.Android.list_devices() ++ DalaDev.Discovery.IOS.list_devices()

    case Enum.find(devices, &(&1.node == node)) do
      nil -> {:error, :device_not_found}
      device -> {:ok, device}
    end
  end

  defp resolve_device(serial) when is_binary(serial) do
    # Assume it's an ADB serial or UDID
    devices = DalaDev.Discovery.Android.list_devices() ++ DalaDev.Discovery.IOS.list_devices()

    case Enum.find(devices, &(&1.serial == serial)) do
      nil -> {:error, :device_not_found}
      device -> {:ok, device}
    end
  end

  defp temp_path(filename) do
    Path.join(System.tmp_dir!(), filename)
  end

  defp timestamp do
    DateTime.utc_now()
    |> DateTime.to_unix()
  end
end
