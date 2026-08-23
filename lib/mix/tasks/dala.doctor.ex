defmodule Mix.Tasks.Dala.Doctor do
  use Mix.Task

  @shortdoc "Check your environment for common Dala setup issues"

  @moduledoc """
  Checks your environment, project configuration, OTP caches, and connected
  devices, reporting any issues with specific fix instructions.

  Run this first when something isn't working:

      mix dala.doctor

  ## What it checks

    1. **Tools**   — adb, xcrun (macOS), Java, Android SDK, iOS build tools
    2. **Project** — dala.exs present, required keys set, paths valid
    3. **Build**   — Elixir deps fetched, project compiled, native build tools present
    4. **OTP cache** — pre-built runtimes downloaded and structurally valid
    5. **Devices** — authorized Android devices and booted iOS simulators

  Exits non-zero if any required checks fail, so it can be used in scripts.
  """

  @impl Mix.Task
  def run(_args) do
    DalaDev.Output.configure([])

    DalaDev.Output.info("")
    DalaDev.Output.step("Dala Doctor")

    issues = []
    issues = issues ++ section("Tools", check_tools())
    issues = issues ++ section("Project", check_project())
    issues = issues ++ section("Build", check_build())
    issues = issues ++ section("OTP Cache", check_otp_cache())
    issues = issues ++ section("Devices", check_devices())
    issues = issues ++ section("Environment", check_environment())

    DalaDev.Output.info("")

    failures = Enum.count(issues, &(&1 == :fail))
    warnings = Enum.count(issues, &(&1 == :warn))

    cond do
      failures > 0 ->
        warn_str =
          if warnings > 0,
            do: ", #{warnings} warning(s)",
            else: ""

        DalaDev.Output.error(
          "#{failures} failure(s)#{warn_str}" <>
            " — fix the issues above and re-run mix dala.doctor."
        )

        Mix.raise("dala.doctor: #{failures} check(s) failed")

      warnings > 0 ->
        DalaDev.Output.warn(
          "#{warnings} warning(s) — optional items above may limit some features."
        )

      true ->
        DalaDev.Output.success("All checks passed.")
    end
  end

  # ── Sections ─────────────────────────────────────────────────────────────────

  # Prints a titled section and returns list of :ok | :warn | :fail atoms.
  defp section(title, checks) do
    DalaDev.Output.info("")
    DalaDev.Output.step(title)

    Enum.map(checks, fn {level, label, detail, fix} ->
      print_check(level, label, detail, fix)
      level
    end)
  end

  # ── Tool checks ──────────────────────────────────────────────────────────────

  defp check_tools do
    List.flatten([
      check_version_manager(),
      check_elixir_versions(),
      check_epmd(),
      check_adb(),
      check_xcrun(),
      if(has_android_project?(), do: check_android_build_tools(), else: []),
      if(has_ios_project?() and macos?(), do: check_ios_build_tools(), else: []),
      check_optional(
        "ideviceinfo",
        :warn,
        "optional — needed for iOS physical device battery benchmarks",
        "brew install libimobiledevice"
      )
    ])
  end

  defp check_version_manager do
    cond do
      path = System.find_executable("mise") ->
        {:ok, "version manager", "mise (#{path})", nil}

      path = System.find_executable("asdf") ->
        {:ok, "version manager", "asdf (#{path})", nil}

      true ->
        {:warn, "version manager", "neither mise nor asdf detected",
         "Dala requires specific Elixir and OTP versions that must match the\n" <>
           "      device runtime. A version manager installs the exact toolchain\n" <>
           "      from your project's .tool-versions file — no manual juggling.\n" <>
           "\n" <>
           "      mise is the modern standard in the Elixir community (fast, cross-platform):\n" <>
           "        brew install mise            https://mise.jdx.dev\n" <>
           "\n" <>
           "      asdf is the established option if you already use it:\n" <>
           "        brew install asdf            https://asdf-vm.com\n" <>
           "\n" <>
           "      After installing, run:  mise install  or  asdf install"}
    end
  end

  defp check_epmd do
    case System.find_executable("epmd") do
      nil ->
        {:fail, "epmd", "not found in PATH — required for Erlang distribution (mix dala.connect)",
         "Ensure OTP's bin directory is in PATH. On Nix: add epmd to your shell environment."}

      path ->
        # Check if it's reachable by attempting a names query
        case System.cmd("epmd", ["-names"], stderr_to_stdout: true) do
          {_, 0} ->
            {:ok, "epmd", path, nil}

          {_, _} ->
            {:warn, "epmd",
             "#{path} found but not running — mix dala.connect will attempt to start it",
             "Run `epmd -daemon` if dala.connect fails to start distribution"}
        end
    end
  end

  @min_elixir "1.18.0"
  @min_otp 26
  @warn_otp 27

  defp check_elixir_versions do
    [check_elixir(), check_otp(), check_hex()]
  end

  defp check_elixir do
    vsn = System.version()

    if Version.compare(vsn, @min_elixir) == :lt do
      {:fail, "Elixir", "#{vsn} — dala requires Elixir #{@min_elixir} or later",
       elixir_upgrade_hint()}
    else
      {:ok, "Elixir", vsn, nil}
    end
  end

  defp check_otp do
    otp = :erlang.system_info(:otp_release) |> to_string()
    n = String.to_integer(otp)

    cond do
      n < @min_otp ->
        {:fail, "OTP", "#{otp} — OTP #{@min_otp} or later required", elixir_upgrade_hint()}

      n < @warn_otp ->
        {:warn, "OTP", "#{otp} — OTP #{@warn_otp}+ recommended (device runtime is OTP 28)",
         elixir_upgrade_hint()}

      true ->
        erts = :erlang.system_info(:version) |> to_string()
        {:ok, "OTP", "#{otp} (ERTS #{erts})", nil}
    end
  end

  defp check_hex do
    vsn =
      case Application.load(:hex) do
        :ok -> Application.spec(:hex, :vsn) |> to_string()
        {:error, {:already_loaded, _}} -> Application.spec(:hex, :vsn) |> to_string()
        {:error, _} -> nil
      end

    cond do
      is_nil(vsn) ->
        {:fail, "Hex", "not installed — required to fetch and manage dependencies",
         "mix local.hex"}

      Version.compare(vsn, "2.0.0") == :lt ->
        {:warn, "Hex", "#{vsn} — version 2.0 or later recommended", "mix local.hex --force"}

      true ->
        {:ok, "Hex", vsn, nil}
    end
  end

  defp elixir_upgrade_hint do
    "Upgrade Elixir to #{@min_elixir} or later. Common methods:\n" <>
      "      mix local.elixir --force      # patch updates within the same minor version\n" <>
      "      mise install elixir@latest    # mise\n" <>
      "      asdf install elixir latest    # asdf\n" <>
      "      brew upgrade elixir           # Homebrew\n" <>
      "      https://elixir-lang.org/install.html"
  end

  defp check_adb do
    case System.find_executable("adb") do
      nil ->
        {:fail, "adb", "required to deploy to Android devices and emulators",
         "Install Android SDK Platform Tools:\n" <>
           "      https://developer.android.com/tools/releases/platform-tools\n" <>
           if(macos?(),
             do: "      or: brew install --cask android-platform-tools",
             else: "      or: sudo apt install adb"
           )}

      path ->
        {:ok, "adb", path, nil}
    end
  end

  defp check_xcrun do
    if macos?() do
      case System.find_executable("xcrun") do
        nil ->
          {:fail, "xcrun", "required to build and run iOS simulator apps",
           "Install Xcode command-line tools:\n      xcode-select --install"}

        _ ->
          case System.cmd("xcodebuild", ["-version"], stderr_to_stdout: true) do
            {out, 0} ->
              version_line = out |> String.split("\n") |> List.first() |> String.trim()

              major =
                Regex.run(Regex.compile!("Xcode (\\d+)"), version_line)
                |> case do
                  [_, v] -> String.to_integer(v)
                  nil -> 99
                end

              if major >= 15 do
                {:ok, "xcrun", version_line, nil}
              else
                {:fail, "xcrun", "Xcode #{major} found — Xcode 15 or later required",
                 "Update Xcode from the App Store or developer.apple.com"}
              end

            _ ->
              {:warn, "xcrun", "found but xcodebuild -version failed", nil}
          end
      end
    else
      {:ok, "xcrun", "skipped (not macOS)", nil}
    end
  end

  @min_jdk 17

  defp check_android_build_tools do
    [
      case System.find_executable("java") do
        nil ->
          {:fail, "java", "required by Gradle to build the Android APK",
           "Install a JDK:\n      macOS:          brew install --cask temurin\n      Ubuntu/Debian:  sudo apt install openjdk-21-jdk\n      Arch:           sudo pacman -S jdk21-openjdk\n      Fedora:         sudo dnf install java-21-openjdk\n      or install Android Studio which bundles a JDK"}

        path ->
          case System.cmd(path, ["-version"], stderr_to_stdout: true) do
            {out, _} ->
              version_line = out |> String.split("\n") |> List.first() |> String.trim()

              major =
                case Regex.run(Regex.compile!("version \"(\\d+)"), version_line,
                       capture: :all_but_first
                     ) do
                  [v] -> String.to_integer(v)
                  _ -> 0
                end

              cond do
                major > 0 and major < @min_jdk ->
                  {
                    :fail,
                    "java",
                    "JDK #{major} found — JDK #{@min_jdk}+ required by Android Gradle Plugin 8.x",
                    "Install a supported JDK:\n      #{java_install_hint()}"
                  }

                major > 21 ->
                  {
                    :warn,
                    "java",
                    "#{version_line} — JDK #{major} detected",
                    "AGP 8.2.0 is tested through JDK 21. JDK #{major} may cause Kotlin compilation errors.\n      Switch to JDK 17 or 21:\n        macOS:          brew install --cask temurin@21 && export JAVA_HOME=$(/usr/libexec/java_home -v 21)\n        Ubuntu/Debian:  sudo apt install openjdk-21-jdk && sudo update-alternatives --config java\n        Arch:           sudo pacman -S jdk21-openjdk && sudo archlinux-java set java-21-openjdk\n        Fedora:         sudo dnf install java-21-openjdk && sudo alternatives --config java"
                  }

                true ->
                  {:ok, "java", version_line, nil}
              end
          end
      end,
      check_android_sdk()
    ]
  end

  defp java_install_hint do
    if macos?() do
      "brew install --cask temurin\n      or install Android Studio which bundles a JDK"
    else
      "sudo apt install openjdk-21-jdk\n" <>
        "      then: export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64\n" <>
        "      or install Android Studio which bundles a JDK"
    end
  end

  defp check_android_sdk do
    sdk_dir =
      System.get_env("ANDROID_HOME") ||
        System.get_env("ANDROID_SDK_ROOT") ||
        read_local_properties_sdk()

    cond do
      is_binary(sdk_dir) and File.dir?(sdk_dir) ->
        {:ok, "Android SDK", sdk_dir, nil}

      is_binary(sdk_dir) ->
        {:fail, "Android SDK", "ANDROID_HOME/ANDROID_SDK_ROOT points to missing path: #{sdk_dir}",
         "Install Android Studio or set ANDROID_HOME to a valid SDK path"}

      true ->
        default_path =
          if macos?(),
            do: "$HOME/Library/Android/sdk",
            else: "$HOME/Android/Sdk"

        {:warn, "Android SDK",
         "ANDROID_HOME not set and sdk.dir not found in android/local.properties",
         "Set ANDROID_HOME in your shell profile:\n" <>
           "      export ANDROID_HOME=#{default_path}\n" <>
           "      or open the android/ folder in Android Studio (it writes local.properties)"}
    end
  end

  defp read_local_properties_sdk do
    path = Path.join(File.cwd!(), "android/local.properties")

    with {:ok, content} <- File.read(path),
         [_, sdk] <- Regex.run(Regex.compile!("^sdk\\.dir=(.+)$", "m"), content) do
      String.trim(sdk)
    else
      _ -> nil
    end
  end

  defp check_ios_build_tools do
    [
      check_required(
        "python3",
        :fail,
        "required by ios/build.sh to detect the booted simulator",
        "python3 is included with macOS Xcode command-line tools:\n      xcode-select --install"
      ),
      check_required(
        "rsync",
        :fail,
        "required by ios/build.sh to sync the OTP runtime to ~/.dala/runtime/ios-sim",
        "rsync is included with macOS — if missing:\n      brew install rsync"
      )
    ]
  end

  defp check_required(cmd, level_if_missing, detail, fix) do
    case System.find_executable(cmd) do
      nil -> {level_if_missing, cmd, detail, fix}
      path -> {:ok, cmd, path, nil}
    end
  end

  defp check_optional(cmd, level_if_missing, detail, fix) do
    check_required(cmd, level_if_missing, detail, fix)
  end

  # ── Project checks ────────────────────────────────────────────────────────────

  defp check_project do
    if File.exists?("mix.exs") do
      do_check_project()
    else
      [{:warn, "project", "not in a Mix project directory — skipping project checks", nil}]
    end
  end

  defp do_check_project do
    dala_exs_check =
      if File.exists?("dala.exs") do
        {:ok, "dala.exs", "found", nil}
      else
        {:fail, "dala.exs", "not found in #{File.cwd!()}", "Run:  mix dala.install"}
      end

    cfg =
      if File.exists?("dala.exs"),
        do: Config.Reader.read!("dala.exs") |> Keyword.get(:dala_dev, []),
        else: []

    [
      dala_exs_check,
      check_cfg_path(
        cfg,
        :dala_dir,
        "path to the dala library repo",
        "Run:  mix dala.install\\n" <>
          "      or add to dala.exs: config :dala_dev, dala_dir: \"/path/to/dala\""
      ),
      check_bundle_id(cfg)
    ]
  end

  defp check_cfg_path(cfg, key, description, fix) do
    val = cfg[key]

    cond do
      is_nil(val) ->
        {:fail, to_string(key), "#{description} — not set in dala.exs", fix}

      is_binary(val) and String.contains?(val, "/path/to/") ->
        {:fail, to_string(key), "still has placeholder value: #{val}", fix}

      is_binary(val) and not File.exists?(Path.expand(val)) ->
        {:fail, to_string(key), "path not found: #{val}",
         "Update dala.exs — the path must exist on this machine"}

      true ->
        {:ok, to_string(key), Path.expand(val), nil}
    end
  end

  defp check_bundle_id(cfg) do
    case cfg[:bundle_id] do
      nil ->
        {:warn, "bundle_id", "not set in dala.exs (only needed for dala.battery_bench)",
         "Add to dala.exs: config :dala_dev, bundle_id: \"com.example.myapp\""}

      id ->
        {:ok, "bundle_id", id, nil}
    end
  end

  # ── Build checks ─────────────────────────────────────────────────────────────

  defp check_build do
    if File.exists?("mix.exs") do
      List.flatten([
        check_deps_fetched(),
        check_compiled()
      ])
    else
      []
    end
  end

  defp check_deps_fetched do
    lock_exists = File.exists?("mix.lock")
    deps_dir = File.exists?("deps") and File.ls!("deps") != []

    cond do
      not lock_exists ->
        {:warn, "mix deps", "mix.lock not found — dependencies have never been fetched",
         "Run:  mix deps.get"}

      not deps_dir ->
        {:fail, "mix deps", "deps/ directory is empty — dependencies not fetched",
         "Run:  mix deps.get"}

      true ->
        # Count packages in lock vs fetched dirs as a quick sanity check
        locked = count_locked_deps()
        fetched = File.ls!("deps") |> length()

        if fetched < locked do
          {:warn, "mix deps",
           "#{fetched} of #{locked} locked deps present in deps/ — may be incomplete",
           "Run:  mix deps.get"}
        else
          {:ok, "mix deps", "#{fetched} deps fetched", nil}
        end
    end
  end

  defp count_locked_deps do
    case File.read("mix.lock") do
      {:ok, content} ->
        # Each dep appears as a quoted key on its own line: "dep_name": {
        content
        |> String.split("\n")
        |> Enum.count(&Regex.match?(Regex.compile!("^\\s+\"[^\"]+\":"), &1))

      _ ->
        0
    end
  end

  defp check_compiled do
    beam_dirs =
      case File.ls("_build/dev/lib") do
        {:ok, libs} ->
          libs
          |> Enum.map(&"_build/dev/lib/#{&1}/ebin")
          |> Enum.filter(&File.dir?/1)
          |> Enum.filter(fn dir ->
            case File.ls(dir) do
              {:ok, files} -> Enum.any?(files, &String.ends_with?(&1, ".beam"))
              _ -> false
            end
          end)

        {:error, _} ->
          []
      end

    cond do
      not File.dir?("_build/dev") ->
        {:fail, "compiled", "_build/dev not found — project has never been compiled",
         "Run:  mix deps.get && mix compile"}

      beam_dirs == [] ->
        {:fail, "compiled", "_build/dev/lib has no compiled BEAMs — nothing to push to devices",
         "Run:  mix compile"}

      true ->
        total_beams =
          Enum.reduce(beam_dirs, 0, fn dir, acc ->
            case File.ls(dir) do
              {:ok, files} -> acc + Enum.count(files, &String.ends_with?(&1, ".beam"))
              _ -> acc
            end
          end)

        {:ok, "compiled", "#{total_beams} BEAMs in #{length(beam_dirs)} lib(s)", nil}
    end
  end

  # ── OTP cache checks ──────────────────────────────────────────────────────────

  defp check_otp_cache do
    checks = [check_otp_dir("Android", DalaDev.OtpDownloader.android_otp_dir())]

    if macos?() do
      checks ++ [check_otp_dir("iOS simulator", DalaDev.OtpDownloader.ios_sim_otp_dir())]
    else
      checks
    end
  end

  defp check_otp_dir(label, dir) do
    name = Path.basename(dir)

    cond do
      not File.dir?(dir) ->
        {:fail, "OTP #{label}", "not downloaded — expected at #{dir}",
         "Run:  mix dala.install\n" <>
           "      (mix dala.deploy --native also downloads automatically)"}

      Path.wildcard(Path.join(dir, "erts-*")) == [] ->
        {:fail, "OTP #{label}",
         "directory exists but no erts-* found — extraction was incomplete",
         "Remove the stale directory and re-download:\n" <>
           "      rm -rf #{dir}\n" <>
           "      mix dala.install"}

      true ->
        erts =
          dir |> Path.join("erts-*") |> Path.wildcard() |> List.first() |> Path.basename()

        {:ok, "OTP #{label}", "#{name} (#{erts})", nil}
    end
  end

  # ── Environment checks ───────────────────────────────────────────────────────

  # Checks for known runtime environment gotchas:
  # - port 4200 squatters (only one Dala LV app can bind per device)
  # - dala / dala_dev version drift across the three-repo topology
  defp check_environment do
    [check_port_4200(), check_version_drift()]
  end

  defp check_port_4200 do
    case System.cmd("lsof", ["-i", ":4200", "-sTCP:LISTEN"], stderr_to_stdout: true) do
      {output, 0} ->
        pids =
          output
          |> String.split("\n")
          |> Enum.drop(1)
          |> Enum.map(&(&1 |> String.split() |> Enum.at(1)))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        if pids == [] do
          {:ok, "Port 4200", "free", nil}
        else
          {:warn, "Port 4200",
           "in use by PID(s): #{Enum.join(pids, ", ")} — a squatter blocks new Dala LV apps from binding",
           "Force-stop the app holding the port, e.g.:\n" <>
             "      adb shell am force-stop <package>   (Android)\n" <>
             "      xcrun simctl terminate booted <bundle-id>   (iOS simulator)"}
        end

      _ ->
        # lsof non-zero usually means nothing is listening — that's fine.
        {:ok, "Port 4200", "free", nil}
    end
  end

  defp check_version_drift do
    dala_version = loaded_app_version(:dala)
    dala_dev_version = loaded_app_version(:dala_dev)

    cond do
      is_nil(dala_version) ->
        {:ok, "Version alignment", "dala not loaded (standalone dala_dev dev)", nil}

      version_drift?(dala_version, dala_dev_version) ->
        {:warn, "Version alignment",
         "dala #{dala_version} vs dala_dev #{dala_dev_version} — minor versions differ",
         "Check all three repos (dala, dala_dev, dala_new) batch together when bumping versions " <>
           "to avoid ghost regressions (see AGENTS.md gotcha #15)"}

      true ->
        {:ok, "Version alignment", "dala #{dala_version} / dala_dev #{dala_dev_version}", nil}
    end
  end

  # Warn when the minor version segments differ (e.g. 0.8.x vs 0.9.x).
  # Patch-level drift is normal and expected.
  defp version_drift?(a, b) do
    parse_minor(a) != parse_minor(b)
  end

  defp parse_minor(version) do
    version
    |> String.split(".")
    |> Enum.take(2)
  end

  defp loaded_app_version(app) do
    case :application.get_key(app, :vsn) do
      {:ok, vsn} -> to_string(vsn)
      _ -> nil
    end
  end

  # ── Device checks ──────────────────────────────────────────────────────────────

  defp check_devices do
    List.flatten([
      check_android_devices(),
      if(macos?(), do: check_ios_simulators(), else: [])
    ])
  end

  defp check_android_devices do
    case System.find_executable("adb") do
      nil ->
        # adb missing — already reported in Tools, skip here
        []

      _ ->
        case System.cmd("adb", ["devices", "-l"], stderr_to_stdout: true) do
          {out, 0} ->
            lines = out |> String.split("\n") |> Enum.drop(1) |> Enum.reject(&(&1 == ""))

            authorized = Enum.filter(lines, &(&1 =~ Regex.compile!("[\\t,\\s]device\\s")))
            unauthorized = Enum.filter(lines, &(&1 =~ "\tunauthorized"))
            offline = Enum.filter(lines, &(&1 =~ "\toffline"))

            results = []

            results =
              results ++
                if authorized == [] do
                  [
                    {:warn, "Android devices", "none authorized",
                     "Connect a device via USB (enable USB Debugging) or start an emulator.\n" <>
                       "      See: https://developer.android.com/studio/debug/dev-options"}
                  ]
                else
                  names =
                    Enum.map_join(authorized, ", ", fn line ->
                      serial = line |> String.split() |> hd()

                      model =
                        case Regex.run(Regex.compile!("model:(\\S+)"), line) do
                          [_, m] -> String.replace(m, "_", " ")
                          nil -> serial
                        end

                      "#{model} (#{serial})"
                    end)

                  [{:ok, "Android devices", names, nil}]
                end

            results =
              results ++
                Enum.map(unauthorized, fn line ->
                  serial = line |> String.split() |> hd()

                  {:warn, "Android device #{serial}",
                   "unauthorized — USB debugging prompt not accepted",
                   "On the device: check for an 'Allow USB debugging?' dialog and tap Allow.\n" <>
                     "      If it doesn't appear, disconnect and reconnect the USB cable."}
                end)

            results =
              results ++
                Enum.map(offline, fn line ->
                  serial = line |> String.split() |> hd()

                  {:warn, "Android device #{serial}",
                   "offline — adb can see the device but cannot communicate",
                   "Try: adb disconnect && adb kill-server && adb devices"}
                end)

            results

          {out, rc} ->
            [
              {:fail, "Android devices", "adb devices failed (exit #{rc}): #{String.trim(out)}",
               "Check adb is working: adb devices"}
            ]
        end
    end
  end

  defp check_ios_simulators do
    case System.find_executable("xcrun") do
      nil ->
        # xcrun missing — already reported in Tools
        []

      _ ->
        case System.cmd("xcrun", ["simctl", "list", "devices", "booted", "--json"],
               stderr_to_stdout: true
             ) do
          {out, 0} ->
            booted =
              case Jason.decode(out) do
                {:ok, %{"devices" => devs}} ->
                  devs
                  |> Map.values()
                  |> List.flatten()
                  |> Enum.filter(&(&1["state"] == "Booted"))

                _ ->
                  []
              end

            if booted == [] do
              [
                {:warn, "iOS simulator", "none booted",
                 "Open Simulator.app, or boot one from the command line:\n" <>
                   "      xcrun simctl list devices available   # find a UDID\n" <>
                   "      xcrun simctl boot <UDID>"}
              ]
            else
              names = Enum.map_join(booted, ", ", &"#{&1["name"]} (#{&1["udid"]})")
              [{:ok, "iOS simulator", names, nil}]
            end

          _ ->
            [{:warn, "iOS simulator", "xcrun simctl failed — cannot list simulators", nil}]
        end
    end
  rescue
    _ -> [{:warn, "iOS simulator", "could not query simulators", nil}]
  end

  # ── Output helpers ────────────────────────────────────────────────────────────

  defp print_check(:ok, label, detail, _fix) do
    suffix = if detail, do: " — #{detail}", else: ""
    DalaDev.Output.success("#{label}#{suffix}")
  end

  defp print_check(:warn, label, detail, fix) do
    suffix = if detail, do: " — #{detail}", else: ""
    DalaDev.Output.warn("#{label}#{suffix}")

    if fix, do: DalaDev.Output.hint(fix)
  end

  defp print_check(:fail, label, detail, fix) do
    suffix = if detail, do: " — #{detail}", else: ""
    DalaDev.Output.error("#{label}#{suffix}")

    if fix, do: DalaDev.Output.hint(fix)
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp has_android_project?, do: File.dir?("android")
  defp has_ios_project?, do: File.exists?("ios/build.sh")
  defp macos?, do: match?({:unix, :darwin}, :os.type())

end
