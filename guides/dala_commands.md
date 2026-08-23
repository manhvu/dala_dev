# Dala Commands Guide

Complete reference for all `mix dala.*` commands with detailed explanations of how they work.

## Table of Contents

- [Core Commands](#core-commands)
  - [mix dala.devices](#mix-daladevices)
  - [mix dala.connect](#mix-dalaconnect)
  - [mix dala.deploy](#mix-daladeploy)
  - [mix dala.server](#mix-dalaserver)
  - [mix dala.emulators](#mix-dalaemulators)
  - [mix dala.doctor](#mix-daladoctor)
  - [mix dala.provision](#mix-dalaprovision)
- [Battery Benchmarking](#battery-benchmarking)
  - [mix dala.battery_bench_android](#mix-dalabattery_bench_android)
  - [mix dala.battery_bench_ios](#mix-dalabattery_bench_ios)
- [Build & Release](#build--release)
  - [mix dala.release](#mix-dalarelease)
  - [mix dala.release.android](#mix-dalareleaseandroid)
  - [mix dala.publish](#mix-dalapublish)
  - [mix dala.publish.android](#mix-dalapublishandroid)
- [Development Tools](#development-tools)
  - [mix dala.watch](#mix-dalawatch)
  - [mix dala.watch_stop](#mix-dalawatch_stop)
  - [mix dala.logs](#mix-dalalogs)
  - [mix dala.screen](#mix-dalascreen)
  - [mix dala.trace](#mix-dalatrace)
  - [mix dala.observer](#mix-dalaobserver)
  - [mix dala.debug](#mix-daladebug)
  - [mix dala.web](#mix-dalaweb)
- [Device Utilities](#device-utilities)
  - [mix dala.reset](#mix-dalareset)
  - [mix dala.shell](#mix-dalashell)
  - [mix dala.port](#mix-dalaport)
  - [mix dala.link](#mix-dalalink)
  - [mix dala.clipboard](#mix-dalaclipboard)
  - [mix dala.location](#mix-dalalocation)
  - [mix dala.env](#mix-dalaenv)
- [Utilities](#utilities)
  - [mix dala.cache](#mix-dalacache)
  - [mix dala.enable](#mix-dalaenable)
  - [mix dala.icon](#mix-dalaicon)
  - [mix dala.routes](#mix-dalaroutes)
  - [mix dala.bench](#mix-dalabench)
  - [mix dala.gen.live_screen](#mix-dalagenlive_screen)
  - [mix dala.install](#mix-dalainstall)
  - [mix dala.push](#mix-dalapush)

---

## Core Commands

### mix dala.devices

**Short description**: List all connected Android and iOS devices

Lists all discovered Android devices (via `adb`) and iOS simulators/physical devices (via `xcrun simctl` / `devicectl`) with their status.

#### Usage

```bash
mix dala.devices
```

#### Output

Shows a table with:
- Status icon (✓ connected, · discovered, ✗ unauthorized, ! error)
- Device name or serial
- OS version
- Device type (physical/simulator/emulator)
- Device ID (for use with `--device` flag)
- IP address (if available)

#### Under the Hood

```bash
# Android discovery
adb devices -l
# → parses serial numbers, device/emulator state, manufacturer/model

# iOS discovery (macOS only)
xcrun simctl list devices booted --json
ideviceinfo -k UniqueDeviceID   (if libimobiledevice is installed)
```

#### Example Output

```
Android
  ✓  Pixel_8_API_34  Android 14  emulator  emulator-5554
  ✓  SM-G998B          Android 13  physical  R3CR50LJN1W

iOS
  ✓  iPhone 15 Pro  iOS 17.2  physical  abc123def456 (192.168.1.42)
  ·  iPad Simulator  iOS 17.2  simulator  789ghi012jkl
```

#### Tips

- Use the displayed ID with `--device` flag for other commands:
  ```bash
  mix dala.deploy --device emulator-5554
  mix dala.deploy --device abc123def456
  ```
- If a device shows "unauthorized", check the device screen for "Allow USB debugging?" prompt
- For Android devices, enable Developer Mode: Settings → About → tap Build Number 7×

---

### mix dala.connect

**Short description**: Connect IEx to all running dala devices

Discovers connected devices, sets up USB tunnels, restarts apps on devices, waits for Erlang nodes to come online, and drops into an IEx session connected to all of them.

#### Usage

```bash
mix dala.connect
```

#### Options

- `--no-iex` — Set up connections but don't start IEx (prints node names instead)
- `--name <node@host>` — Local node name (default: `dala_dev@127.0.0.1`)
- `--cookie <cookie>` — Erlang cookie (default: `dala_secret`)

#### Multiple Simultaneous Sessions

You can run multiple independent sessions by using different node names:

```bash
# Terminal 1 — interactive developer session
mix dala.connect --name dala_dev_1@127.0.0.1

# Terminal 2 — agent or second developer
mix dala.connect --name dala_dev_2@127.0.0.1
```

Both see the same live device state and can call `Dala.Test.*` and `nl/1` independently.

#### IEx + Dashboard Combined

For an interactive session alongside the dev dashboard:

```bash
iex -S mix dala.server
```

This starts the dashboard at `localhost:4040` and gives you an IEx prompt in the same process.

#### iOS Physical Device Connectivity

Physical iPhones support three connection modes (auto-detected at BEAM startup):

| Priority | Connection | Node Name | When |
|----------|------------|-----------|------|
| 1 | WiFi / LAN | `<app>_ios@10.0.0.x` | On the same network as the Mac |
| 1 | Tailscale | `<app>_ios@100.x.x.x` | Any network — see below |
| 2 | USB only | `<app>_ios@169.254.x.x` | Cable plugged in, no WiFi |
| 3 | None | `<app>_ios@127.0.0.1` | No network |

**WiFi** is preferred over USB so the node IP stays stable across cable plug/unplug.

**Tailscale** lets you connect over any network including cellular. Install on both Mac and iPhone, sign in to the same account, and `mix dala.connect` works regardless of network.

#### Under the Hood

```bash
# Android: set up adb port tunnels
adb reverse tcp:4369 tcp:4369   # EPMD: device → Mac
adb forward tcp:9100 tcp:9100   # dist port: Mac → device

# iOS simulator shares Mac's network stack — no tunnelling needed
# iOS physical: BEAM registers its own in-process EPMD on device

# Then in Elixir:
Node.start(:"dala_dev@127.0.0.1", :longnames)
Node.set_cookie(:dala_secret)
Node.connect(:"my_app_android@127.0.0.1")
Node.connect(:"my_app_ios@127.0.0.1")
```

---

### mix dala.deploy

**Short description**: Build and deploy to all connected dala devices

Compiles the project and pushes BEAM files to all connected Android devices and iOS simulators.

#### Usage

```bash
mix dala.deploy
mix dala.deploy --native
mix dala.deploy --device <id>
```

#### Modes

**Fast deploy** (default) — Push BEAMs + restart. Use for day-to-day Elixir code changes. Requires the native app already installed on device.

```bash
mix dala.deploy
```

**Full deploy** — Build native binary + install APK/app + push BEAMs. Use the first time or after changes to native C/Java/Swift code.

```bash
mix dala.deploy --native
```

#### Options

- `--native` — Build native binaries before pushing BEAMs
- `--no-restart` — Push BEAMs but don't restart the app
- `--device <id>` — Target a specific device (use `mix dala.devices` to find IDs)
- `--all` — Target every connected device; with `--native --ios`, builds **both** the physical iPhone and the simulator instead of letting the physical branch win silently
- `--schedulers <N>` — Set BEAM scheduler count (saved to dala.exs)
- `--beam-flags "<flags>"` — Arbitrary BEAM flags string (saved to dala.exs)

#### BEAM Scheduler Tuning

The default native build uses `1:1` (single scheduler) for battery efficiency.

```bash
# Pin to 2 schedulers
mix dala.deploy --schedulers 2

# Let BEAM auto-detect — one scheduler per logical core
mix dala.deploy --schedulers 0

# Arbitrary flags (replaces --schedulers)
mix dala.deploy --beam-flags "-S 4:4 -A 4"
```

The chosen value is written to `dala.exs` under `beam_flags:` and reused on subsequent runs.

#### Under the Hood

**Fast deploy** (equivalent to):

```bash
mix compile

# Android
adb push _build/prod/lib/*/ebin/*.beam /data/data/<pkg>/files/lib/*/ebin/
adb shell am force-stop <package>               # restart

# iOS simulator
xcrun simctl spawn <udid> cp <beam_files> <app_bundle>/
```

When Erlang distribution is reachable, hot-pushes via RPC instead:

```elixir
:rpc.call(node, :code, :load_binary, [Module, path, beam_binary])
```

**Full deploy** (additionally):

```bash
# Android
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk

# iOS simulator
xcodebuild -scheme <app> -destination 'platform=iOS Simulator,...' build
xcrun simctl install booted <app>.app
```

---

### mix dala.server

**Short description**: Start the Dala dev server (localhost:4040)

Starts a Phoenix-based development dashboard with live device status and controls.

#### Usage

```bash
mix dala.server
mix dala.server --port 4040   # default port
```

#### Features

- Live device status cards (Android + iOS simulator)
- Per-device deploy buttons ("Update" and "First Deploy")
- Streaming log panel (logcat / iOS simulator console)
- Watch mode for auto-pushing changed BEAMs

#### IEx + Dashboard

For an interactive IEx session alongside the dashboard:

```bash
iex -S mix dala.server
```

#### Under the Hood

```elixir
Application.ensure_all_started(:bandit)
Application.ensure_all_started(:phoenix_live_view)

Supervisor.start_link([
  {Phoenix.PubSub, name: DalaDev.PubSub},
  DalaDev.Server.Endpoint,          # Bandit HTTP server on port 4040
  DalaDev.Server.DevicePoller,      # polls adb + xcrun simctl
  DalaDev.Server.LogStreamerSupervisor,  # logcat / simctl log streams
  DalaDev.Server.WatchWorker,       # optional file-watch loop
  ...
], strategy: :one_for_one)

open "http://localhost:4040"       # macOS: open, Linux: xdg-open
```

The endpoint uses `Bandit.PhoenixAdapter` instead of Cowboy.

---

### mix dala.emulators

**Short description**: List, start, and stop Android emulators / iOS simulators

Manages virtual devices: Android emulators (AVDs) and iOS simulators.

#### Usage

```bash
mix dala.emulators                        # list all (default)
mix dala.emulators --list                 # same as above
mix dala.emulators --list --android       # Android only
mix dala.emulators --list --ios           # iOS only

mix dala.emulators --start --id Pixel_8_API_34
mix dala.emulators --start --id 78354490
mix dala.emulators --start --id Pixel_8_API_34 --recipe selinux-off
mix dala.emulators --start --id Pixel_8_API_34 --emulator_args "-no-audio -gpu host"

mix dala.emulators --stop --id emulator-5554
mix dala.emulators --stop --id 78354490
mix dala.emulators --stop --all           # everything booted
```

#### Options

- `--list` — List all emulators/simulators
- `--start` — Start an emulator/simulator (requires `--id`)
- `--stop` — Stop an emulator/simulator (requires `--id` or `--all`)
- `--android` — Filter to Android only
- `--ios` — Filter to iOS only
- `--id <id>` — Emulator/simulator ID (from `mix dala.emulators --list`)
- `--all` — Apply to all running emulators/simulators
- `--recipe <name>` — Android launch preset: `selinux-off`, `cold-boot`, `wipe-data`, `no-audio`, `gpu-host`
- `--emulator_args "<flags>"` — Free-form Android emulator CLI flags

#### Notes

- `--id` accepts the same display IDs `mix dala.devices` shows, plus AVD names
- For Android, the running serial (`emulator-5554`) also works
- Recipes/flags apply to Android emulators only; they are ignored (with a warning) for iOS simulators
- `selinux-off` is the workaround for the Android 17 preview where BEAM startup dies on cgroup SELinux denials — dev-only, never on real hardware (`wipe-data` is destructive)
- Creating new AVDs or installing simulator runtimes is out of scope — use Android Studio / Xcode for that

---

### mix dala.doctor

**Short description**: Diagnose common setup and configuration issues

Runs a comprehensive diagnostic check on your development environment.

#### Usage

```bash
mix dala.doctor
```

#### What It Checks

**System Tools:**
- adb (Android Debug Bridge)
- xcrun (Xcode command-line tools)
- EPMD (Erlang Port Mapper)

**Version Managers:**
- asdf, mise, or other version managers

**Elixir & OTP:**
- Elixir version compatibility
- OTP version compatibility
- Hex package manager

**Android Setup:**
- Android SDK location
- Build tools version
- Platform tools

**iOS Setup (macOS only):**
- Xcode installation
- Command-line tools
- Provisioning profiles

**Project Configuration:**
- `dala.exs` configuration
- Bundle ID setup
- Dependencies fetched
- Project compiled
- OTP cache valid

**Connected Devices:**
- Android devices connected
- iOS simulators running

#### Output Levels

- ✓ **OK** — Check passed
- ⚠ **WARN** — Issue but can proceed (e.g., free Apple developer account)
- ✗ **FAIL** — Blocking issue that needs resolution

---

### mix dala.provision

**Short description**: Register your app ID and download an iOS provisioning profile

Registers your app's bundle ID with Apple and downloads an iOS provisioning profile.

#### Usage

```bash
mix dala.provision                 # development profile (default)
mix dala.provision --distribution  # App Store distribution profile
```

#### Prerequisites

1. **Apple ID** — free at https://appleid.apple.com
2. **Xcode signed in** with that Apple ID:
   - Open Xcode → Settings → Accounts → [+] → Apple ID
3. **Apple Developer Program** — optional for personal device development, required for App Store distribution ($99/year)
   - Free accounts can deploy to their own devices (profiles expire every 7 days)
   - Paid accounts get 1-year profiles and App Store access

#### What It Does (Development Mode)

1. Reads your signing team from the macOS keychain or existing profiles
2. Generates `ios/Provision.xcodeproj` — a minimal Xcode project for provisioning
3. Generates `ios/DalaProvision.swift` — a two-line SwiftUI stub
4. Runs `xcodebuild -allowProvisioningUpdates build` which contacts Apple to:
   - Register your bundle ID in your developer account (if not registered)
   - Create a development provisioning profile
   - Download it to `~/Library/Developer/Xcode/.../Provisioning Profiles/`
5. Verifies the profile is present

#### What It Does (Distribution Mode)

Same as above, but runs `xcodebuild archive -allowProvisioningUpdates` with `CODE_SIGN_STYLE=Automatic` against the Release configuration. Creates an App Store provisioning profile and downloads it to your keychain + provisioning profile directory.

#### When to Run

- **Development**: Run once before your first `mix dala.deploy --native`
- **Distribution**: Run once before your first `mix dala.release`

---

## Battery Benchmarking

### mix dala.battery_bench_android

**Short description**: Run a battery benchmark on an Android device

Builds a benchmark APK, deploys it, and measures battery drain over time. Reports mAh every 10 seconds and prints a summary at the end.

#### Usage

```bash
mix dala.battery_bench_android
mix dala.battery_bench_android --no-beam
mix dala.battery_bench_android --preset nerves
mix dala.battery_bench_android --flags "-sbwt none -S 1:1"
mix dala.battery_bench_android --duration 3600 --device 192.168.1.42:5555
mix dala.battery_bench_android --no-build   # re-run without rebuilding
```

#### Setup (One-Time, While Plugged In)

WiFi ADB is required for accurate measurements (USB cable charges the battery).

```bash
adb -s SERIAL tcpip 5555
adb connect PHONE_IP:5555
# then unplug and pass PHONE_IP:5555 as --device
```

#### Recommended Workflow

Two-step pattern (push BEAM flags via `mix dala.deploy`, then bench with `--no-build`):

```bash
# 1. Push BEAM flags via dala.deploy (no APK rebuild — ~10 sec).
mix dala.deploy --beam-flags "" --android              # tuned (Nerves)
mix dala.deploy --beam-flags "-S 4:4 -A 8" --android   # untuned variant

# 2. Run the bench with --no-build.
mix dala.battery_bench_android --no-build --device 192.168.1.42:5555
```

#### Options

- `--duration N` — Benchmark duration in **seconds** (default: 1800 = 30 min)
- `--device SERIAL` — adb device serial or IP:port (auto-detected if omitted)
- `--no-beam` — Baseline: build without starting the BEAM at all
- `--no-keep-alive` — Skip the foreground-service background keep-alive call
- `--preset NAME` — Named BEAM flag preset (Gradle-build path only)
- `--flags "..."` — Arbitrary BEAM VM flags (Gradle-build path only)
- `--no-build` — Skip APK build and install; run benchmark on current install
- `--log-path PATH` — Override CSV log location (default: `_build/bench/run_android_<ts>.csv`)
- `--no-csv` — Skip CSV logging
- `--skip-preflight` — Bypass the preflight checks (adb/app/BEAM/RPC/NIF/keep-alive)

#### Presets

| Preset | Description | Flags |
|--------|-------------|-------|
| `untuned` | Raw BEAM with no tuning (highest power use) | (none) |
| `sbwt` | Only busy-wait disabled | `-sbwt none` |
| `nerves` | Full Nerves set: single scheduler + busy-wait off + multi_time_warp | `-sbwt none -S 1:1 -MBen 1` |
| (default) | Same as `nerves` | `-sbwt none -S 1:1 -MBen 1` |

#### Understanding Results

- The BEAM with Nerves-style tuning uses ~same power as an app with no BEAM at all (~200 mAh/hr on a Moto G, 30-min run)
- The untuned BEAM uses ~25% more power due to scheduler busy-waiting
- For most apps the overhead is in the noise; tune only if you have stricter power budgets

---

### mix dala.battery_bench_ios

**Short description**: Run a battery benchmark on an iOS device

Similar to the Android version but for iOS devices. Measures battery drain over time with support for different BEAM tuning configurations.

#### Usage

```bash
mix dala.battery_bench_ios
mix dala.battery_bench_ios --no-beam
mix dala.battery_bench_ios --preset nerves
mix dala.battery_bench_ios --wifi-ip 192.168.1.42
mix dala.battery_bench_ios --no-build
```

#### Options

Similar to Android version, plus:
- `--wifi-ip IP` — iOS device IP address for WiFi connection
- `--simulator` — Run on iOS simulator instead of physical device

#### Flag Prefix Convention (iOS)

iOS uses a different flag prefix convention than Android. See the full documentation in `README.md` for details.

---

## Build & Release

### mix dala.release

**Short description**: Build a release for distribution

Builds a release of your app for App Store or enterprise distribution.

#### Usage

```bash
mix dala.release
mix dala.release --ios
mix dala.release --android
```

#### Options

- No options — builds signed .ipa for the configured signing identity and provisioning profile

---

### mix dala.release.android

**Short description**: Build an Android release APK/AAB

Builds a signed Android release APK or Android App Bundle (AAB) for Play Store distribution.

#### Usage

```bash
mix dala.release.android
```

#### Options

- No options — builds signed .aab for the configured signing identity

#### Under the Hood

```bash
./gradlew bundleRelease   # or assembleRelease
# Signs and aligns the APK/AAB
# Outputs to android/app/build/outputs/
```

---

### mix dala.publish

**Short description**: Publish release to app stores

Publishes your built release to the App Store or Play Store.

#### Usage

```bash
mix dala.publish
```

---

### mix dala.publish.android

**Short description**: Publish Android app to Play Store

Uploads your Android app bundle to the Google Play Store.

#### Usage

```bash
mix dala.publish.android
mix dala.publish.android --track internal
mix dala.publish.android --track production
```

#### Options

- `--track TRACK` — Release track (internal, alpha, beta, production)

Note: Requires Google Play service account JSON configured in `dala.exs`.

---

## Development Tools

### mix dala.watch

**Short description**: Watch for file changes and auto-deploy

Watches your Elixir source files and automatically deploys changes to connected devices.

#### Usage

```bash
mix dala.watch
mix dala.watch --debounce 500
```

#### Options

- `--cookie <cookie>` — Erlang cookie (default: `dala_secret`)
- `--debounce <ms>` — ms to wait after a change before compiling (default: 300)
- `--interval <ms>` — ms between file-change polls (default: 500)

---

### mix dala.watch_stop

**Short description**: Stop the file watcher

Stops the background file watcher started by `mix dala.watch`.

#### Usage

```bash
mix dala.watch_stop
```

---

### mix dala.logs

**Short description**: Stream device logs

Streams logs from connected devices (logcat for Android, console for iOS).

#### Usage

```bash
mix dala.logs
mix dala.logs --device <id>
mix dala.logs --follow
```

#### Options

- `--device <id>` — Stream logs from specific device
- `--follow` — Continue streaming logs (like `tail -f`)
- `--level <level>` — Filter by log level (debug, info, warn, error)

---

### mix dala.screen

**Short description**: Capture screenshots and record video from devices

Takes screenshots or records video from connected devices.

#### Usage

```bash
mix dala.screen --capture --save-as screen.png
mix dala.screen --record --duration 30 --save-as demo.mp4
mix dala.screen --preview
```

---

### mix dala.trace

**Short description**: Trace function calls on device

Runs `:dbg` tracing on a connected device to debug function calls.

#### Usage

```bash
mix dala.trace MyModule.my_function/2
mix dala.trace --node my_app_android@127.0.0.1
```

---

### mix dala.observer

**Short description**: Launch observer on remote node

Opens the Erlang Observer GUI connected to a remote device node.

#### Usage

```bash
mix dala.observer
mix dala.observer --node my_app_ios@192.168.1.42
```

---

### mix dala.debug

**Short description**: Debug helper with breakpoints

Sets up debugging sessions with breakpoint support on connected devices.

#### Usage

```bash
mix dala.debug
mix dala.debug --iex
```

---

### mix dala.web

**Short description**: Start comprehensive web UI for all dala_dev features

Starts the full web UI with device management, deployment controls, log streaming, cluster visualization, and design tools.

#### Usage

```bash
mix dala.web
```

---

## Device Utilities

Small commands that remove recurring friction when working with emulators,
simulators, and physical devices.

### mix dala.reset

**Short description**: Force-stop Dala app processes on devices, optionally wipe data

More thorough than an app restart. On Android it force-stops **both** the
project package and the `com.dala.<app>` wrapper (whose
`BeamForegroundService` outlives the Activity — see `docs/reference/issues.md`
#11), then clears the logcat buffer so the next launch starts clean.

#### Usage

```bash
mix dala.reset                     # stop apps on all devices
mix dala.reset --device 5554       # one device only
mix dala.reset --data              # also wipe app data
```

#### Notes

- Android: `am force-stop` both packages + `logcat -c`; `--data` adds `pm clear`
- iOS Simulator: `simctl terminate`; `--data` adds `simctl uninstall`
- Physical iOS: not supported — stop the app from the device itself

---

### mix dala.shell

**Short description**: Shell into the app sandbox on a connected device

Drops you into (or runs commands inside) the app's private data directory,
without retyping serials/UDIDs.

#### Usage

```bash
mix dala.shell                          # print the command for your shell
mix dala.shell --exec "ls -la"          # run one command inside the sandbox
mix dala.shell --exec "cat files/x.txt" --device 5554
mix dala.shell --bundle com.example.myapp
```

#### Notes

- Android: interactive `adb shell run-as <bundle>`; `--exec` runs via `run-as -c`
- iOS Simulator: prints the data container path (`xcrun simctl get_app_container … data`);
  `--exec` runs a shell from that directory
- Physical iOS: not supported (no public sandbox exec)
- Without `--exec`, the exact command is printed for copy-paste — interactive TTY
  sessions are more reliable from your own terminal than through Mix

---

### mix dala.port

**Short description**: Show dala's port map per device and find host-side squatters

Prints which host ports belong to which device and flags processes squatting
on them (stale iproxy, previous BEAM instances).

#### Usage

```bash
mix dala.port                # table: device → dist / LV ports + status
mix dala.port --kill         # free ports held by stale processes
mix dala.port --json         # machine-readable
```

Ports covered: EPMD (4369), per-device dist (9100+), and the project's
hashed LiveView port (4200–4999).

---

### mix dala.link

**Short description**: Open a URL / deep link on connected devices

The dev-machine side of `Dala.Platform.Linking`.

#### Usage

```bash
mix dala.link https://example.com
mix dala.link myapp://product/42 --device 78354490
```

Android uses `am start -a android.intent.action.VIEW -d <url>`;
iOS Simulator uses `xcrun simctl openurl`. Any URL scheme is accepted
(https or custom app schemes); scheme-less strings are rejected.

---

### mix dala.clipboard

**Short description**: Read or set the device clipboard (iOS Simulator)

Paste long strings into device text fields without typing them on the
virtual keyboard.

#### Usage

```bash
mix dala.clipboard get                     # print clipboard contents
mix dala.clipboard set "some long token"   # replace clipboard contents
mix dala.clipboard get --device 78354490
```

Supported on iOS Simulators (`xcrun simctl pbpaste/pbcopy`). Modern Android
blocks background clipboard access — use `adb shell input text "…"` with the
field focused instead.

---

### mix dala.location

**Short description**: Spoof the device location (emulator / simulator)

Pins a device's location for testing `Dala.Platform.Location` without moving.

#### Usage

```bash
mix dala.location set 21.0278,105.8342
mix dala.location set 37.7749,-122.4194 --device 5554
mix dala.location reset                     # stop spoofing (iOS Simulator)
```

Works on Android **emulators** (`adb emu geo fix`) and iOS Simulators
(`xcrun simctl location`). Physical devices need platform tooling.

---

### mix dala.env

**Short description**: Print a machine-readable snapshot of the dala dev environment

One-shot inventory: host toolchain versions, Android/iOS tool availability,
project bundle id, and every connected device with its node name and dist port.
Unlike `mix dala.doctor`, this diagnoses nothing — it answers "what do I have"
for scripts, CI logs, and bug reports.

#### Usage

```bash
mix dala.env            # human-readable summary
mix dala.env --json     # single JSON document
```

---

## Utilities

### mix dala.cache

**Short description**: Show or clear machine-wide caches

Shows cached OTP runtimes and other cached data, or clears them to force re-download.

#### Usage

```bash
mix dala.cache          # show cache info
mix dala.cache --clear  # clear all caches
```

#### Options

- `--clear` — Clear all cached data

---

### mix dala.enable

**Short description**: Enable optional Dala features

Enables optional native features like camera, photo library, location, etc. Updates `dala.exs` with required permissions and adds necessary native code.

#### Usage

```bash
mix dala.enable --list          # show available features
mix dala.enable camera          # enable camera
mix dala.enable photo_library   # enable photo library
mix dala.enable location        # enable location services
mix dala.enable liveview        # enable LiveView mode
```

---

### mix dala.icon

**Short description**: Generate app icons

Generates app icons in all required sizes for Android and iOS from a source image.

#### Usage

```bash
mix dala.icon path/to/icon.png
```

---

### mix dala.routes

**Short description**: Validate navigation routes

Validates navigation routes in your app and checks for broken links.

#### Usage

```bash
mix dala.routes
mix dala.routes --verbose
```

---

### mix dala.bench

**Short description**: Run performance benchmarks

Runs performance benchmarks on your Elixir code.

#### Usage

```bash
mix dala.bench
mix dala.bench --test test/my_bench.exs
mix dala.bench --compare node1@host,node2@host
mix dala.bench --report report.html --format html
```

---

### mix dala.gen.live_screen

**Short description**: Generate a LiveView screen

Generates a new Phoenix LiveView screen with boilerplate code.

#### Usage

```bash
mix dala.gen.live_screen MyScreen
```

---

### mix dala.install

**Short description**: First-run setup

Downloads OTP runtime, generates icons, writes `dala.exs`. Run once per project.

#### Usage

```bash
mix dala.install
```

---

### mix dala.push

**Short description**: Hot-push changed BEAM files to device

Pushes only changed BEAM modules to connected devices via Erlang distribution (no restart required). This is the primary day-to-day development command for quick iteration.

#### Usage

```bash
mix dala.push
mix dala.push --device <id>
```

---

## Quick Reference

| Command | Description | Key Options |
|---------|-------------|-------------|
| `mix dala.devices` | List connected devices | — |
| `mix dala.connect` | Connect IEx to devices | `--no-iex`, `--name`, `--cookie` |
| `mix dala.deploy` | Deploy to devices | `--native`, `--device`, `--all`, `--schedulers`, `--beam-flags` |
| `mix dala.server` | Start dev dashboard | `--port` |
| `mix dala.emulators` | Manage emulators | `--list`, `--start`, `--stop`, `--id`, `--recipe` |
| `mix dala.reset` | Force-stop apps (+ wipe data) | `--data`, `--device` |
| `mix dala.shell` | Shell into the app sandbox | `--exec`, `--bundle_id`, `--device` |
| `mix dala.port` | Port map + squatter detection | `--kill`, `--json` |
| `mix dala.link` | Open a URL / deep link | `--device` |
| `mix dala.clipboard` | Device clipboard get/set | `get`, `set "text"`, `--device` |
| `mix dala.location` | Spoof device location | `set <lat>,<lng>`, `reset`, `--device` |
| `mix dala.env` | Environment snapshot (JSON) | `--json` |
| `mix dala.doctor` | Diagnose setup issues | — |
| `mix dala.provision` | iOS provisioning | `--distribution` |
| `mix dala.battery_bench_android` | Android battery bench | `--duration`, `--preset`, `--no-build` |
| `mix dala.battery_bench_ios` | iOS battery bench | `--duration`, `--wifi-ip`, `--no-build` |
| `mix dala.release` | Build iOS release | — |
| `mix dala.watch` | Auto-deploy on file change | `--cookie`, `--debounce` |
| `mix dala.logs` | Stream device logs | `--device`, `--follow` |
| `mix dala.cache` | Show or clear caches | `--clear` |

---

## See Also

- [README.md](../README.md) — Project overview and architecture
- [AGENTS.md](../AGENTS.md) — Developer guide for contributing
- [build_release.md](../build_release.md) — Release build walkthrough
- [release_and_packaging.md](release_and_packaging.md) — Building and distributing production apps
