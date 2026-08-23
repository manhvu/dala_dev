defmodule DalaDev.AppReset do
  @moduledoc """
  Force-stops Dala app processes on connected devices and optionally wipes
  their app data — a clean-slate reset without reinstalling.

  Exists because a plain Activity restart is not a full restart on Android:
  `BeamForegroundService` outlives the Activity, so the BEAM keeps running
  with old NIFs and BEAMs loaded (see docs/reference/issues.md #11). A reset
  force-stops **both** packages — the project bundle and the dala wrapper
  package (`com.dala.<app>`) that hosts the foreground service — then clears
  the logcat buffer so the next launch's output is easy to read.
  """

  alias DalaDev.{Config, Device, Utils}
  alias DalaDev.Discovery.{Android, IOS}

  @type result :: {:ok, String.t()} | {:error, String.t()}
  @type opts :: keyword()

  # ── Pure builders (public test seams) ───────────────────────────────────────

  @doc """
  Returns the Android packages to stop: the project bundle id plus the dala
  wrapper package (`com.dala.<app>`). Deduplicated — when the bundle id is
  already the wrapper form there is exactly one entry.
  """
  @spec android_packages(opts()) :: [String.t()]
  def android_packages(opts \\ []) do
    main = Keyword.get(opts, :bundle_id) || Config.bundle_id()
    app_name = Keyword.get_lazy(opts, :app_name, &app_name/0)
    Enum.uniq([main, "com.dala." <> app_name])
  end

  @doc """
  adb argument lists that stop the app and clear the logcat buffer. Pure —
  no adb calls. Exposed for testing.
  """
  @spec android_stop_commands(String.t(), [String.t()]) :: [[String.t()]]
  def android_stop_commands(serial, packages) do
    stop = Enum.map(packages, &["-s", serial, "shell", "am", "force-stop", &1])
    clear_logs = [["-s", serial, "logcat", "-c"]]
    stop ++ clear_logs
  end

  @doc "adb argument lists that wipe each package's data (`pm clear`)."
  @spec android_clear_data_commands(String.t(), [String.t()]) :: [[String.t()]]
  def android_clear_data_commands(serial, packages) do
    Enum.map(packages, &["-s", serial, "shell", "pm", "clear", &1])
  end

  @doc """
  simctl argument lists for an iOS simulator: terminate the app (ignored when
  not running) plus uninstall when wiping data. Pure — no simctl calls.
  """
  @spec ios_sim_commands(String.t(), String.t(), boolean()) :: [{[String.t()], boolean()}]
  def ios_sim_commands(udid, bundle_id, clear_data?) do
    base = [
      {["simctl", "terminate", udid, bundle_id], false},
      {["simctl", "terminate", udid, "com.dala." <> app_name()], false}
    ]

    if clear_data? do
      base ++ [{["simctl", "uninstall", udid, bundle_id], true}]
    else
      base
    end
  end

  # ── Dispatch ────────────────────────────────────────────────────────────────

  @doc """
  Resets one device. Returns `{:ok, summary}` or `{:error, reason}`.

  Options:

    * `:clear_data` - also wipe app data (`pm clear` / `simctl uninstall`)
    * `:bundle_id` - override the resolved bundle id
  """
  @spec reset(Device.t(), opts()) :: result()
  def reset(%Device{platform: :android, serial: serial} = _device, opts) do
    packages = android_packages(opts)

    commands =
      android_stop_commands(serial, packages) ++
        if Keyword.get(opts, :clear_data, false),
          do: android_clear_data_commands(serial, packages),
          else: []

    exec = Keyword.get(opts, :exec, &default_exec/1)

    failures =
      commands
      |> Enum.map(fn args -> exec.({:adb, args}) end)
      |> Enum.filter(&match?({:error, _}, &1))

    case failures do
      [] -> {:ok, "stopped #{Enum.join(packages, ", ")}"}
      _ -> {:error, "#{length(failures)} of #{length(commands)} adb command(s) failed"}
    end
  end

  def reset(%Device{platform: :ios, type: :simulator, serial: udid}, opts) do
    bundle = Keyword.get(opts, :bundle_id) || Config.bundle_id()
    clear_data? = Keyword.get(opts, :clear_data, false)
    exec = Keyword.get(opts, :exec, &default_exec/1)

    failures =
      ios_sim_commands(udid, bundle, clear_data?)
      |> Enum.reject(fn {_args, ignore_failure} -> ignore_failure end)
      |> Enum.map(fn {args, _} -> exec.({:xcrun, args}) end)
      |> Enum.filter(&match?({:error, _}, &1))

    case failures do
      [] -> {:ok, "terminated #{bundle}" <> if(clear_data?, do: " + uninstalled", else: "")}
      _ -> {:error, "#{length(failures)} simctl command(s) failed"}
    end
  end

  def reset(%Device{platform: :ios}, _opts) do
    {:error,
     "reset needs a booted simulator — physical iOS has no CLI terminate; stop the app on the device"}
  end

  @doc """
  Resets matching devices (all connected by default).

  Options: `:device`, `:clear_data`, `:bundle_id`, plus the test seams
  `:devices` (explicit device list) and `:exec` (command executor override —
  receives tagged `{:adb, args}` / `{:xcrun, args}`, returns
  `{:ok, out}` / `{:error, out_or_reason}`).

  Returns a list of `{label, result}` tuples in discovery order.
  """
  @spec reset_all(opts()) :: [{String.t(), result()}]
  def reset_all(opts \\ []) do
    device_id = Keyword.get(opts, :device)

    devices =
      (Keyword.get(opts, :devices) || Android.list_devices() ++ IOS.list_devices())
      |> Enum.reject(&(&1.status == :unauthorized))
      |> filter_by_device(device_id)

    reset_devices(devices, opts)
  end

  @doc """
  Resets an explicit device list. Public test seam used by `reset_all/1`.
  """
  @spec reset_devices([Device.t()], opts()) :: [{String.t(), result()}]
  def reset_devices(devices, opts) do
    Enum.map(devices, fn device ->
      label = device.name || device.serial
      {label, reset(device, opts)}
    end)
  end

  # ── Internals ───────────────────────────────────────────────────────────────

  # Executes a tagged command, normalizing both tool outputs to
  # `{:ok, output}` / `{:error, output_or_reason}`.
  defp default_exec({:adb, args}), do: Utils.run_adb_with_timeout(args, timeout: 10_000)

  defp default_exec({:xcrun, args}) do
    case System.cmd("xcrun", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, _} -> {:error, String.trim(out)}
    end
  end

  defp filter_by_device(devices, nil), do: devices

  defp filter_by_device(devices, id), do: Enum.filter(devices, &Device.match_id?(&1, id))

  defp app_name, do: Mix.Project.config()[:app] |> to_string()
end
