defmodule Mix.Tasks.Dala.Screen do
  use Mix.Task

  @shortdoc "Capture screenshots, record video, or preview screen from mobile devices"

  @moduledoc """
  Capture screenshots, record screen video, or start live screen preview
  from connected mobile devices.

  ## Examples

      # Take a screenshot (auto-detects device)
      mix dala.screen --capture

      # Save screenshot to file
      mix dala.screen --capture screenshot.png

      # Record 30 seconds of video
      mix dala.screen --record --duration 30

      # Start live preview in browser
      mix dala.screen --preview

      # Specify device by node
      mix dala.screen --node dala_qa@192.168.1.5 --capture

      # Screenshot baselines (visual regression)
      mix dala.screen --baseline home          # save baseline "home"
      mix dala.screen --compare home           # re-capture and compare

      # List available devices
      mix dala.screen --list

  ## Options

    * `--capture` - Take a screenshot
    * `--record` - Record screen video
    * `--preview` - Start live screen preview
    * `--baseline <name>` - Save a named screenshot baseline for this device
    * `--compare <name>` - Re-capture and compare against the baseline
    * `--node` - Target device node or serial
    * `--duration` - Recording duration in seconds (default: 30)
    * `--save-as` - Output file path
    * `--list` - List available devices
    * `--port` - Preview server port (default: 5050)

  Baselines are stored per-device under `.dala/screenshots/`. A comparison
  match means the screen is byte-identical to the baseline; on a difference,
  the fresh capture is saved as `<name>.new.png` next to it.
  """

  alias DalaDev.{ScreenCapture, ScreenBaseline, Discovery}

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])
    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          capture: :boolean,
          record: :boolean,
          preview: :boolean,
          node: :string,
          duration: :integer,
          save_as: :string,
          list: :boolean,
          port: :integer,
          baseline: :string,
          compare: :string
        ],
        aliases: [
          c: :capture,
          r: :record,
          p: :preview,
          n: :node,
          d: :duration,
          s: :save_as
        ]
      )

    cond do
      Keyword.get(opts, :list, false) ->
        list_devices()

      Keyword.get(opts, :preview, false) ->
        start_preview(opts)

      Keyword.get(opts, :record, false) ->
        record_screen(opts)

      name = opts[:baseline] ->
        save_baseline(opts, name)

      name = opts[:compare] ->
        compare_baseline(opts, name)

      Keyword.get(opts, :capture, false) or Keyword.has_key?(opts, :save_as) ->
        capture_screen(opts)

      true ->
        show_usage()
    end
  end

  defp list_devices do
    android = Discovery.Android.list_devices()
    ios = Discovery.IOS.list_devices()

    if android == [] and ios == [] do
      DalaDev.Output.info("No devices found.")
      DalaDev.Output.info("Connect an Android device or start an iOS simulator.")
    else
      DalaDev.Output.info("Available devices:\n")

      Enum.each(android, fn device ->
        DalaDev.Output.info("  Android: #{device.name || device.serial} (#{device.serial})")
      end)

      Enum.each(ios, fn device ->
        DalaDev.Output.info("  iOS: #{device.name || device.serial} (#{device.serial})")
      end)
    end
  end

  defp start_preview(opts) do
    device_ref = get_device_ref(opts)

    case ScreenCapture.live_preview(device_ref, port: Keyword.get(opts, :port, 5050)) do
      {:ok, _pid} ->
        DalaDev.Output.info("\nPress Ctrl+C to stop the preview server.")

        # Keep running until user interrupts
        Process.sleep(:infinity)

      {:error, reason} ->
        DalaDev.Output.error("Failed to start preview: #{inspect(reason)}")
    end
  rescue
    e ->
      DalaDev.Output.error("Error: #{Exception.message(e)}")
  end

  defp capture_screen(opts) do
    device_ref = get_device_ref(opts)
    save_as = Keyword.get(opts, :save_as)

    capture_opts =
      if save_as do
        [save_as: save_as]
      else
        []
      end

    DalaDev.Output.info("Capturing screenshot...")

    case ScreenCapture.capture(device_ref, capture_opts) do
      {:ok, path} when is_binary(path) ->
        DalaDev.Output.info("Screenshot saved to: #{path}")

      {:ok, png_data} when is_binary(png_data) ->
        if save_as do
          File.write!(save_as, png_data)
          DalaDev.Output.info("Screenshot saved to: #{save_as}")
        else
          DalaDev.Output.info("Screenshot captured (#{byte_size(png_data)} bytes)")
          DalaDev.Output.info("Use --save-as to save to file")
        end

      {:error, reason} ->
        DalaDev.Output.error("Failed to capture screenshot: #{inspect(reason)}")
    end
  end

  defp save_baseline(opts, name) do
    device = get_device_ref(opts)

    case ScreenBaseline.save(device, name) do
      {:ok, path} ->
        DalaDev.Output.info("Baseline \"#{name}\" saved: #{path}")

      {:error, reason} ->
        DalaDev.Output.error("Failed to save baseline: #{inspect(reason)}")
    end
  end

  defp compare_baseline(opts, name) do
    device = get_device_ref(opts)

    case ScreenBaseline.compare(device, name) do
      {:ok, :match} ->
        DalaDev.Output.info("#{IO.ANSI.green()}✓ #{name}: matches baseline#{IO.ANSI.reset()}")

      {:ok, {:changed, details}} ->
        DalaDev.Output.error("✗ #{name}: differs from baseline")
        DalaDev.Output.info("  baseline: #{details.baseline} (#{details.size_a} bytes)")
        DalaDev.Output.info("  current:  #{details.current} (#{details.size_b} bytes)")

      {:error, :no_baseline} ->
        DalaDev.Output.error("No baseline named \"#{name}\" — save one with --baseline #{name}")

      {:error, reason} ->
        DalaDev.Output.error("Failed to compare: #{inspect(reason)}")
    end
  end

  defp record_screen(opts) do
    device_ref = get_device_ref(opts)
    duration = Keyword.get(opts, :duration, 30)
    save_as = Keyword.get(opts, :save_as, "screen_record_#{timestamp()}.mp4")

    DalaDev.Output.info("Recording for #{duration} seconds...")

    record_opts = [duration: duration, save_as: save_as]

    case ScreenCapture.record(device_ref, record_opts) do
      {:ok, path} ->
        DalaDev.Output.info("\nRecording saved to: #{path}")

      {:error, reason} ->
        DalaDev.Output.error("Failed to record: #{inspect(reason)}")
    end
  end

  defp get_device_ref(opts) do
    case Keyword.get(opts, :node) do
      nil ->
        # Auto-detect first available device
        devices = DalaDev.Discovery.Android.list_devices() ++ DalaDev.Discovery.IOS.list_devices()

        case devices do
          [] ->
            Mix.raise("No devices found. Connect a device or use --node to specify one.")

          [device | _] ->
            DalaDev.Output.info("Using device: #{device.name || device.serial}")
            device
        end

      node_str ->
        # Try to parse as node atom, or use as serial
        case node_str do
          "dala_qa@" <> _ = node_str -> String.to_atom(node_str)
          _ -> node_str
        end
    end
  end

  defp timestamp do
    DateTime.utc_now()
    |> DateTime.to_unix()
  end

  defp show_usage do
    DalaDev.Output.info("""
    Usage: mix Dala.Screen [OPTIONS]

    Options:
      --capture, -c           Take a screenshot
      --record, -r            Record screen video
      --preview, -p           Start live screen preview
      --baseline <name>       Save a named screenshot baseline
      --compare <name>        Compare against a baseline
      --node, -n <node>       Target device node or serial
      --duration, -d <secs>   Recording duration (default: 30)
      --save-as, -s <path>    Output file path
      --port <port>           Preview server port (default: 5050)
      --list                  List available devices

    Examples:
      mix Dala.Screen --capture
      mix Dala.Screen --record --duration 60
      mix Dala.Screen --preview --port 8080
    """)
  end
end
