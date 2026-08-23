defmodule Mix.Tasks.Dala.Deploy do
  use Mix.Task

  @shortdoc "Build and deploy to all connected dala devices"

  @moduledoc """
  Compiles the project then pushes BEAM files to all connected
  Android devices and iOS simulators.

  ## Modes

  **Fast deploy** (default) — push BEAMs + restart. Use this for day-to-day
  Elixir code changes. Requires the native app already installed on device.

      mix dala.deploy

  **Full deploy** — build native binary + install APK/app + push BEAMs.
  Use this the first time, or after changes to native C/Java/Swift code.

      mix dala.deploy --native

  ## Options

    * `--native`              — build native binaries before pushing BEAMs
    * `--no-restart`          — push BEAMs but don't restart the app
    * `--device <id>`         — target a specific device; use `mix dala.devices` to find IDs
    * `--schedulers <N>`      — set BEAM scheduler count (saved to dala.exs)
    * `--beam-flags "<flags>"` — arbitrary BEAM flags string (saved to dala.exs)
    * `--dry-run`             — show what would be deployed without deploying
    * `--quiet`               — suppress non-essential output (errors only)
    * `--json`                — emit machine-readable JSON summary

  ## BEAM scheduler tuning

  The default native build uses `1:1` (single scheduler) for battery efficiency.
  Override for the current deploy and all future deploys until changed:

      # Pin to 2 schedulers
      mix dala.deploy --schedulers 2

      # Let BEAM auto-detect — one scheduler per logical core
      mix dala.deploy --schedulers 0

      # Arbitrary flags (replaces --schedulers)
      mix dala.deploy --beam-flags "-S 4:4 -A 4"

  The chosen value is written to `dala.exs` under `beam_flags:` and reused on
  subsequent `mix dala.deploy` runs that don't pass either flag. The flags are
  written alongside the BEAMs as a `dala_beam_flags` file that the native launcher
  reads at startup — no APK/app rebuild required.

  ## Under the hood

  A fast deploy is equivalent to:

      mix deps.get                                     # only with --native
      mix compile

      # Android
      adb push _build/prod/lib/*/ebin/*.beam /data/data/<pkg>/files/lib/*/ebin/
      adb shell am force-stop <package>               # restart

      # iOS simulator
      xcrun simctl spawn <udid> cp <beam_files> <app_bundle>/

  When Erlang distribution is already reachable (app running, node connected),
  `mix dala.deploy` skips `adb push` and hot-pushes via RPC instead — equivalent
  to calling `nl(Module)` in IEx for every changed module:

      :rpc.call(node, :code, :load_binary, [Module, path, beam_binary])

  With `--native`, it also runs the platform build before pushing BEAMs:

      # Android
      ./gradlew assembleDebug
      adb install -r app/build/outputs/apk/debug/app-debug.apk

      # iOS simulator
      xcodebuild -scheme <app> -destination 'platform=iOS Simulator,...' build
      xcrun simctl install booted <app>.app
  """

  @switches [
    native: :boolean,
    restart: :boolean,
    android: :boolean,
    ios: :boolean,
    device: :string,
    all: :boolean,
    schedulers: :integer,
    beam_flags: :string,
    quiet: :boolean,
    json: :boolean,
    dry_run: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    DalaDev.Output.configure(quiet: opts[:quiet], json: opts[:json])

    restart = Keyword.get(opts, :restart, true)
    native = Keyword.get(opts, :native, false)
    device_id = opts[:device]
    deploy_all_devices? = Keyword.get(opts, :all, false)
    platforms = resolve_platforms(opts)

    # Narrow once at the task level so build_all and deploy_all both see the
    # same platform list. Without this, the deployer iterates over the
    # irrelevant platform and `filter_by_device_id` emits a misleading
    # "No device matched" warning even when the targeted platform succeeded.
    platforms =
      if deploy_all_devices? do
        platforms
      else
        DalaDev.NativeBuild.narrow_platforms_for_device(platforms, device_id)
      end

    beam_flags = resolve_beam_flags(opts)

    # When no --device is given and we're doing a native iOS build, auto-detect
    # a connected physical device now so both the native build and the BEAM push
    # target the same device (not all simulators + the phone).
    #
    # --all reverses that: no single-device narrowing, and the native build
    # covers every available iOS target (physical + simulator) instead of
    # letting the physical branch win silently.
    effective_device_id =
      cond do
        deploy_all_devices? -> nil
        device_id -> device_id
        native and :ios in platforms -> DalaDev.NativeBuild.detect_physical_ios()
        true -> nil
      end

    DalaDev.Output.info("")

    if deploy_all_devices? do
      DalaDev.Output.info("--all: targeting every connected device")
    end

    if native do
      DalaDev.Output.step("Fetching dependencies")
      mix = System.find_executable("mix")
      System.cmd(mix, ["deps.get"], into: IO.stream())
    end

    Mix.Task.run("compile")

    if opts[:dry_run] do
      run_dry_run(platforms, effective_device_id, deploy_all_devices?)
    else
      run_deploy(
        opts,
        restart,
        native,
        platforms,
        effective_device_id,
        device_id,
        beam_flags,
        deploy_all_devices?
      )
    end
  end

  defp run_dry_run(platforms, device_id, all_devices?) do
    DalaDev.Output.step("Dry run — no changes will be made")

    devices = discover_devices(platforms, if(all_devices?, do: nil, else: device_id))

    if devices == [] do
      DalaDev.Output.warn("No devices found for platforms: #{inspect(platforms)}")
      DalaDev.Output.hint("Run `mix dala.devices` to see what's connected")
    else
      Enum.each(devices, fn d ->
        DalaDev.Output.info("  would deploy to: #{DalaDev.Device.summary(d)}")
      end)

      beam_dirs = DalaDev.Deployer.collect_beam_dirs()

      DalaDev.Output.info("  would push #{DalaDev.Deployer.count_beams(beam_dirs)} BEAM file(s)")

      DalaDev.Output.info("  native build: skipped (dry run)")
    end

    DalaDev.Output.success("Dry run complete — nothing was deployed")
  end

  defp discover_devices(platforms, device_id) do
    android =
      if :android in platforms,
        do: DalaDev.Discovery.Android.list_devices() |> filter_devices(device_id),
        else: []

    ios =
      if :ios in platforms and macos?(),
        do: DalaDev.Discovery.IOS.list_devices() |> filter_devices(device_id),
        else: []

    android ++ ios
  end

  defp filter_devices(devices, nil), do: devices

  defp filter_devices(devices, id),
    do: Enum.filter(devices, &DalaDev.Device.match_id?(&1, id))

  defp run_deploy(
         opts,
         restart,
         native,
         platforms,
         effective_device_id,
         device_id,
         beam_flags,
         all_devices?
       ) do
    DalaDev.Output.info("")

    native_ok =
      if native do
        DalaDev.NativeBuild.build_all(
          platforms: platforms,
          device: effective_device_id,
          all_devices: all_devices?
        )
      end

    # Skip BEAM push if native build failed — the APK/app bundle isn't installed
    # so run-as / simctl push would fail with misleading errors.
    if native and native_ok == false do
      DalaDev.Output.error("Native build had failures — see errors above.")

      DalaDev.Output.hint(
        "Run `mix dala.doctor` to check your environment, or `mix dala.deploy` (without --native) once the issue is fixed."
      )

      Mix.raise("Native build failed")
    end

    {deployed, failed} =
      DalaDev.Output.timed("Deploying to devices", fn ->
        DalaDev.Deployer.deploy_all(
          restart: restart,
          platforms: platforms,
          force_fs: native,
          device: device_id,
          ios_device: effective_device_id,
          beam_flags: beam_flags
        )
      end)

    if opts[:json] do
      DalaDev.Output.info(
        Jason.encode!(%{
          deployed: Enum.map(deployed, &device_json/1),
          failed: Enum.map(failed, &device_json/1)
        })
      )
    else
      summarize(deployed, failed, restart)
    end
  end

  defp device_json(d) do
    %{name: d.name, serial: d.serial, platform: d.platform, status: d.status, error: d.error}
  end

  defp summarize(deployed, failed, restart) do
    if deployed == [] and failed == [] do
      DalaDev.Output.warn("No devices found.")
      DalaDev.Output.hint("Run `mix dala.devices` to diagnose connection issues")
    else
      if deployed != [] do
        DalaDev.Output.success("Deployed to #{length(deployed)} device(s)")

        if restart do
          DalaDev.Output.hint("Apps restarted. Run `mix dala.connect` to open IEx.")
        else
          DalaDev.Output.hint("BEAMs pushed. In IEx: nl(MyModule) to hot-load.")
        end
      end

      if failed != [] do
        DalaDev.Output.error("Failed on #{length(failed)} device(s)")

        Enum.each(failed, fn d ->
          DalaDev.Output.error("  #{d.name || d.serial}: #{d.error}")
        end)
      end
    end
  end

  defp resolve_platforms(opts) do
    android = opts[:android]
    ios = opts[:ios]

    cond do
      android && ios ->
        [:android, :ios]

      android ->
        [:android]

      ios ->
        if macos?() do
          [:ios]
        else
          DalaDev.Output.warn("--ios is only supported on macOS. Skipping iOS.")

          []
        end

      macos?() ->
        [:android, :ios]

      true ->
        [:android]
    end
  end

  defp macos?, do: match?({:unix, :darwin}, :os.type())

  # Resolve --schedulers / --beam-flags into a combined flags string, save to
  # dala.exs, and return it (or the previously saved value if no flags given).
  defp resolve_beam_flags(opts) do
    new_flags = combine_beam_flags(opts[:schedulers], opts[:beam_flags])

    if new_flags do
      save_beam_flags(new_flags)
      "#{IO.ANSI.cyan()}* beam flags: #{new_flags} (saved to dala.exs)#{IO.ANSI.reset()}"
      new_flags
    else
      DalaDev.Config.load_dala_config()[:beam_flags]
    end
  end

  @doc false
  @spec combine_beam_flags(pos_integer() | nil, String.t() | nil) :: String.t() | nil
  def combine_beam_flags(schedulers, flags_string) do
    case {schedulers, flags_string} do
      {nil, nil} -> nil
      {n, nil} -> "-S #{n}:#{n}"
      {nil, flags} -> String.trim(flags)
      {n, flags} -> "-S #{n}:#{n} #{String.trim(flags)}"
    end
  end

  # Write or update the beam_flags key in dala.exs.
  defp save_beam_flags(flags) do
    path = Path.join(File.cwd!(), "dala.exs")
    unless File.exists?(path), do: Mix.raise("dala.exs not found in current directory")

    content = File.read!(path)
    updated = update_beam_flags_in_config(content, flags)
    File.write!(path, updated)
  end

  @doc false
  @spec update_beam_flags_in_config(String.t(), String.t() | nil) :: String.t()
  def update_beam_flags_in_config(content, flags) do
    value = inspect(flags)

    if content =~ Regex.compile!("^\\s+beam_flags:", "m") do
      Regex.replace(
        Regex.compile!("^(\\s+beam_flags:).*$", "m"),
        content,
        "  beam_flags: #{value}"
      )
    else
      String.trim_trailing(content) <> "\nconfig :dala_dev, beam_flags: #{value}\n"
    end
  end
end
