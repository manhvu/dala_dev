# AGENTS.md — dala_dev

You're in **dala_dev**, the build/deploy/devices toolkit for the dala ecosystem. This repository contains Mix tasks and supporting modules that handle:
- Building and deploying Elixir/OTP applications to mobile devices
- Discovering and managing connected Android and iOS devices
- Running emulators and simulators
- Provisioning development certificates and profiles
- Cross-compiling OTP releases for mobile platforms
- Performance benchmarking and battery profiling on devices
- Cluster visualization and distributed tracing

**Important**: Read the Dala repo's [`AGENTS.md`](/Users/manhvu/ohhi/OSS_Lib/dala/AGENTS.md) first for the system-wide view, the three-repo topology (dala, dala_dev, dala_new), and the cross-cutting pre-empt-failure rules that apply across all repositories. The notes below are dala_dev-specific conventions and gotchas.

**Dala v0.8.0** introduces a plugin architecture where Dala core knows almost nothing — plugins self-describe through schema, commands, and native capabilities. See the `Dala.Plugin` section below. New in this version: GPU render surface with compute shaders, media runtime (video, scene graph, GPU filters, GPU processor), ML stack (Nx, EMLX, CoreML, ONNX, Burn with serving/training, GPU inference), expanded platform APIs (Clipboard, Share, Location, Notify, Diag, PubSub, Registry, Permissions, LiveView), NFC, screen manager, adaptive theming, a comprehensive two-layer testing model (render tree + native UI), Spark DSL with transformers and compile-time verification (`Dala.Spark.DslVerifier`, `Dala.Spark.DslCompileHook`), a `Dala.Designer` dev tool (renamed from `Dala.Preview`), new Mix tasks (`mix dala.verify`, `mix dala.plugin.new`, `mix dala.setup_bluetooth_wifi`), platform-specific setup modules (`Dala.Setup.Android`, `Dala.Setup.Ios`), and new facade modules (Dala.Component, Dala.ComponentServer, Dala.ComponentRegistry, Dala.Diff, Dala.List, Dala.Event, Dala.PubSub, Dala.Native NIF fallbacks).

## What this repo is

This repository provides the command-line tooling and library code for mobile development workflows with Elixir/OTP.

**Dual licensed under:**
- **MIT License** (for original Mob project portions) - see [LICENSE](LICENSE)
- **MPL 2.0** (for new contributions) - see [LICENSE-MPL2.0](LICENSE-MPL2.0)

See [NOTICE](NOTICE) for attribution details.

### Mix Tasks (User-facing commands)

These are the commands users run via `mix dala.<task>`:

**Deployment and connection**:
- **`mix dala.deploy`** — Deploy builds to connected devices or emulators
- **`mix dala.push`** — Hot-push changed modules to running devices (no restart)
- **`mix dala.connect`** — Connect to a running device/emulator session
- **`mix dala.watch`** — Auto-push BEAMs on file save
- **`mix dala.watch_stop`** — Stop a running watch session

**Device management**:
- **`mix dala.devices`** — List discovered Android and iOS devices
- **`mix dala.emulators`** — Manage and launch emulators/simulators (`--recipe selinux-off`, `--emulator_args`)
- **`mix dala.screen`** — Capture screenshots, record video, preview screen, screenshot baselines (`--baseline <name>`, `--compare <name>`)
- **`mix dala.reset`** — Force-stop Dala app processes on devices (both packages), clear logcat; `--data` wipes app data
- **`mix dala.shell`** — Shell into the app sandbox on a device (`run-as` / sim container), or run one-shot commands with `--exec`
- **`mix dala.port`** — Show dala's port map per device and detect/kill host-side port squatters
- **`mix dala.link`** — Open a URL / deep link on connected devices
- **`mix dala.clipboard`** — Read or set the device clipboard (iOS Simulator)
- **`mix dala.location`** — Spoof the device location on emulators/simulators

**Build and release**:
- **`mix dala.release`** — Build a signed iOS .ipa for App Store / TestFlight
- **`mix dala.release.android`** — Build a signed Android .aab for Google Play
- **`mix dala.publish`** — Upload .ipa to App Store Connect / TestFlight
- **`mix dala.publish.android`** — Upload .aab to Google Play Console

**Project setup**:
- **`mix dala.install`** — First-run setup: download OTP runtime, generate icons, write `dala.exs`
- **`mix dala.enable`** — Enable optional Dala features (camera, photo_library, etc.)
- **`mix dala.icon`** — Regenerate app icons from a source image
- **`mix dala.cache`** — Show or clear machine-wide caches
- **`mix dala.doctor`** — Diagnose common setup and configuration issues
- **`mix dala.provision`** — Handle iOS provisioning profiles and certificates
- **`mix dala.routes`** — Validate navigation destinations across the codebase

**Development tools**:
- **`mix dala_dev.tui`** — Launch interactive TUI dashboard for devices, tasks, and deployments
- **`mix dala.server`** — Start dev dashboard (Phoenix, localhost:4040)
- **`mix dala.web`** — Start comprehensive web UI for all dala_dev features
- **`mix dala.gen.live_screen`** — Generate a LiveView + Dala.Screen pair
- **`mix dala.debug`** — Interactive debugging for dala nodes
- **`mix dala.observer`** — Web-based Observer for remote node monitoring
- **`mix dala.logs`** — Collect and stream logs from devices and cluster nodes
- **`mix dala.trace`** — Distributed tracing for dala clusters
- **`mix dala.bench`** — Run performance benchmarks on dala nodes
- **`mix dala.env`** — Machine-readable snapshot of the dev environment (toolchains, project, devices; `--json`)

**Dala framework tasks** (from the dala repo, available in Dala projects):
- **`mix dala.verify`** — Verify Dala DSL definitions and project configuration (`--dsl`, `--components`, `--strict`)
- **`mix dala.plugin.new`** — Generate a new Dala plugin scaffold
- **`mix dala.setup_bluetooth_wifi`** — Set up Bluetooth/WiFi permissions for both platforms (`--platform ios|android`, `--check`)
- **`mix dala.setup_ios_bluetooth`** — Set up iOS Bluetooth specifically (`--check`)
- **`mix dala.onboarding_test`** — Run onboarding tests for Dala projects

**File transfer**:
- **`mix dala.push_file`** — Push a file or directory to connected devices
- **`mix dala.pull_file`** — Pull a file or directory from a connected device
- **`mix dala.sync`** — Sync a local directory with a device directory (bidirectional with delete)
- **`mix dala.file_ls`** — List files in a directory on a connected device

**Battery benchmarking**:
- **`mix dala.battery_bench_android`** — Android battery benchmarking
- **`mix dala.battery_bench_ios`** — iOS battery benchmarking

### Core Modules (Library code)

- **`DalaDev.Discovery.Android`** — Discovers Android devices via `adb`, parses device listings
- **`DalaDev.Discovery.IOS`** — Discovers iOS simulators and devices via `xcrun simctl` and `devicectl`
- **`DalaDev.NativeBuild`** — Cross-compilation logic for Android (arm64/arm32) and iOS (simulator/device)
- **`DalaDev.OtpDownloader`** — Downloads and caches pre-built OTP tarballs for mobile platforms
- **`DalaDev.Deployer`** — Handles the deployment pipeline: build → package → install → launch
- **`DalaDev.HotPush`** — Hot-pushes changed BEAM modules via RPC (no restart)
- **`DalaDev.Emulators`** — Manages emulator lifecycle and configuration
- **`DalaDev.Connector`** — Discovery → tunnel → restart → connect orchestration
- **`DalaDev.Tunnel`** — Port tunneling (adb forward/reverse, iproxy)
- **`DalaDev.Device`** — Unified device struct with common interface
- **`DalaDev.Config`** — Configuration handling (dala.exs)
- **`DalaDev.Utils`** — Centralized utility functions (regex compilation, ADB helpers)
- **`DalaDev.AppReset`** — Force-stop app packages (incl. the `com.dala.<app>` wrapper), clear logcat, optional data wipe
- **`DalaDev.DeviceShell`** — Command builders for shelling into an app's sandbox (`run-as`, sim container)
- **`DalaDev.Ports`** — Per-device port map (EPMD/dist/LV) and host-side squatter detection
- **`DalaDev.DeepLink`** — Open URLs / deep links on devices
- **`DalaDev.DeviceClipboard`** — Device clipboard read/write (iOS Simulator)
- **`DalaDev.LocationSpoof`** — Location spoofing on emulators/simulators
- **`DalaDev.EnvSnapshot`** — Machine-readable dev-environment inventory
- **`DalaDev.ScreenBaseline`** — Screenshot baselines for visual regression
- **`DalaDev.Paths`** — Path resolution for OTP runtimes, SDKs, and build artifacts
- **`DalaDev.CrashDump`** — Crash dump parsing and HTML report generation
- **`DalaDev.Benchmark`** — Performance benchmarking utilities
- **`DalaDev.Profiling`** — Profiling and flame graph generation
- **`DalaDev.Tracing`** — Distributed tracing infrastructure
- **`DalaDev.Network`** — Network diagnostics and device connectivity
- **`DalaDev.LogCollector`** — Log collection and streaming from devices
- **`DalaDev.FileTransfer`** — File/folder push, pull, sync, and ls for connected devices
- **`DalaDev.ScreenCapture`** — Screenshot and video capture from devices
- **`DalaDev.Debugger`** — Interactive remote debugging
- **`DalaDev.Observer`** — Remote node observation (web-based :observer)
- **`DalaDev.QR`** — QR code generation for device connectivity

### Release Engineering (`scripts/release/`)

The **release tooling** directory contains shell scripts that:
1. Cross-compile OTP for target platforms:
   - Android arm64 and arm32 (using NDK toolchain)
   - iOS simulator (x86_64 and arm64)
   - iOS device (arm64)
2. Stage compiled tarballs with metadata
3. Upload releases to GitHub Releases

**Patches for OTP**: iOS device builds require source patches in `scripts/release/patches/`:
- `forker_start` skip — Avoids fork issues on iOS
- EPMD `NO_DAEMON` guard — Prevents EPMD daemonization on iOS

See `build_release.md` for the complete release walkthrough with step-by-step instructions.

## Test-Driven Development (TDD)

TDD is the standard practice in this repository. This ensures reliability across platforms and makes refactoring safer.

### Testing Strategy

- **Write tests first**: Before implementing a new function or fixing a bug, write a test that captures the expected behavior
- **Test alongside code**: For simple changes, write tests in the same working session
- **Every function needs tests**: Public API functions, parsing logic, and platform-specific code paths all need coverage
- **Keep the suite green**: All tests must pass before merging. A failing test is a blocker.

### Running Tests

```bash
# Run the full test suite
mix test

# Run only unit tests (skip integration tests that need devices)
mix test --exclude integration

# Run a specific test file
mix test test/path/to/test_file.exs

# Run tests matching a pattern
mix test --only describe:"feature name"
```

### Integration Tests

Integration tests (tagged with `@tag :integration`) require connected devices or running emulators. These are excluded by default in CI and during development unless explicitly enabled.

## Gotchas and Common Pitfalls

These are issues that have caused problems in the past. Learn from our mistakes to avoid wasting time debugging them again.

### 1. Compile-time Regex Literals (Elixir 1.19 / OTP 28.0+)

**Problem**: Regex literals in module attributes or function heads are compiled at compile time, which can cause issues with certain OTP versions. OTP 28.0 removed `:re.import/1` which compile-time `~r//` literals depend on.

**Solution**: Always use runtime compilation with `Regex.compile!("...", "flags")` or `DalaDev.Utils.compile_regex/2` for dynamic or potentially problematic patterns.

**Status**: Already fixed in 0.3.17, but easy to reintroduce. 71 literals were swept in that release. Don't use `~r{...}` syntax for patterns that might be problematic.

```elixir
# ❌ DON'T — compile-time regex
@pattern ~r/foo.*bar/

# ✅ DO — runtime compilation
@pattern Regex.compile!("foo.*bar", "")

# ✅ DO — centralized utility
@pattern DalaDev.Utils.compile_regex("foo.*bar")
```

### 2. Device ID Resolution in `mix dala.deploy`

**Problem**: When deploying with `--device <id>`, the system must resolve the device ID through discovery before deciding which platform to build for.

**Key function**: `DalaDev.NativeBuild.narrow_platforms_for_device/2`

**Why it matters**: This function is the **single source of truth** for both:
- Determining build targets (which platforms to compile for)
- Validating deployment targets (which devices are valid)

**Consequence of bypassing**: If you skip this function:
- Deploy: You'll get spurious "No device matched" warnings
- Build: You'll build for the wrong platform (e.g., building iOS when you need Android)

**Rule**: Always call `narrow_platforms_for_device/2` when resolving device IDs.

### 3. Xcodebuild Error Diagnostics

**Problem**: `xcodebuild` produces cryptic error messages that are hard to interpret.

**Solution**: `DalaDev.Provision.diagnose_xcodebuild_failure/1` rewrites Apple's errors into actionable hints.

**How it works**:
- Takes raw `xcodebuild` output
- Pattern matches against known error strings
- Returns a structured hint with:
  - Apple's original error text (preserved for Google-ability)
  - Our human-friendly explanation
  - Suggested fix actions

**When to update**: Whenever you encounter a new Apple error string that isn't handled, add a new pattern match in `diagnose_xcodebuild_failure/1`.

### 4. OTP Tarball Schema Versioning

**Problem**: When we change the structure of OTP tarballs (e.g., adding new files, changing directory layout), cached downloads become invalid.

**Solution**: Bump the schema version in `DalaDev.OtpDownloader.valid_otp_dir?/2`.

**Important**: 
- **DO NOT** bump the OTP hash — that's for checksum verification
- **DO** bump the schema version — that's the knob for invalidating caches

**How it works**: `valid_otp_dir?/2` checks if a cached tarball matches the expected schema version. If the schema changes, the cache is invalidated and the tarball is re-downloaded.

### 5. Release Script Assumptions

**Problem**: The release scripts in `scripts/release/` assume a specific directory structure.

**Key assumption**: `~/code/otp` must exist with the correct cross-compile output.

**Patch application**: The patches in `scripts/release/patches/` are applied automatically by `xcompile_ios_device.sh`.

**Idempotency**: The patch application is idempotent — re-running the script is safe and won't cause issues.

**Setup**: If you're setting up a release build environment:
```bash
mkdir -p ~/code/otp
# Follow instructions in build_release.md for populating this directory
```

### 6. Default Arguments Evaluate Eagerly

**Problem**: `System.get_env("ROOTDIR", Path.expand("~/..."))` evaluates `Path.expand` *every call*, regardless of whether `ROOTDIR` is set. `Path.expand("~/...")` calls `System.user_home!()` which raises on Android (no `HOME` env var).

**Solution**: Use `case System.get_env(...)` or `||` instead.

```elixir
# ❌ DON'T — eager evaluation
System.get_env("ROOTDIR", Path.expand("~/otp"))

# ✅ DO — lazy evaluation
System.get_env("ROOTDIR") || Path.expand("~/otp")
```

**Reference**: Burned us once — see dala commit `d77932e`.

### 7. iOS Device Sandbox Blocks `fork()`

**Problem**: The BEAM's `forker_start` and EPMD's `run_daemon` both call fork, which is blocked by the iOS device sandbox.

**Solution**: Both are patched in our OTP cross-compile. Patches at `scripts/release/patches/`.

**Rule**: Don't undo them. These patches are essential for iOS device builds.

### 8. iOS Sim and iOS Device Are Different Build Paths

**Problem**: Sim → `ios/build.sh` (`build_ios/1` in NativeBuild). Device → `ios/build_device.sh` (`build_ios_physical/2`). These are completely different build chains.

**Solution**: When `--device <udid>` is passed, dala_dev resolves it via `IOS.list_devices/0` to know which path to take.

**Rule**: Don't shortcut — always go through device resolution to pick the right build path.

### 9. LV Port 4200 Is Global Per Device

**Problem**: Two installed Dala LV apps + one running = the second can't bind.

**Workaround**: Force-stop the squatter.

**Tracked**: `issues.md` #4 (hash bundle id into port).

### 10. `:dala_nif.log/1` for Early Startup Logging

**Problem**: `Logger` output goes to stderr and is invisible before `Dala.App.start` runs `Dala.Platform.NativeLogger.install()` (which reroutes Logger to NSLog/logcat).

**Solution**: Use `:dala_nif.log("message")` for diagnostics during early init (steps 1–4 in the Erlang bootstrap).

**Rule**: `:dala_nif.log/1` for early startup, `Logger` after `Dala.App.start`.

### 11. Android Distribution Startup Race

**Problem**: Android cannot start distribution at BEAM launch — races with hwui thread pool cause SIGABRT via FORTIFY `pthread_mutex_lock on destroyed mutex`.

**Solution**: `Dala.Connectivity.Dist.ensure_started/1` defers `Node.start/2` by 3 seconds after app startup. This is handled in the dala library.

**Also**: ERTS helper binaries (`erl_child_setup`, `inet_gethost`, `epmd`) cannot be exec'd from the app data directory (SELinux `app_data_file` blocks `execute_no_trans`). They are packaged in the APK as `lib*.so` in `jniLibs/arm64-v8a/` (gets `apk_data_file` label, which allows exec). `dala_beam.c` symlinks `BINDIR/<name>` → `<nativeLibraryDir>/lib<name>.so` before `erl_start`.

### 12. EPMD Tunneling Differences

**Problem**: iOS simulator and Android have different tunneling requirements.

**iOS simulator**: Shares the Mac's network stack — the iOS BEAM registers directly in the Mac's EPMD on port 4369. No forwarding needed.

**Android**: Separate network namespace. `dala_dev` sets up adb tunnels automatically:
```
adb reverse tcp:4369 tcp:4369   # EPMD: device → Mac (Android BEAM registers in Mac EPMD)
adb forward tcp:9100 tcp:9100   # dist:  Mac → device
```

**Port assignment**: Devices are assigned dist ports by index to avoid conflicts:
- Device 0 (Android): port 9100
- Device 1 (iOS sim): port 9101

### 13. Android Node Naming

**Problem**: Android node names include a serial suffix to distinguish multiple devices.

**Convention**:
- iOS simulator: `dala_demo_ios@127.0.0.1`
- Android: `dala_demo_android_<serial-suffix>@127.0.0.1`

**Note**: The serial suffix comes from `ro.serialno`. Multi-Android support is still pending — `MainActivity.java` does NOT yet read the `dala_dist_port` intent extra.

### 14. Struct Fields Used in Guards/Pattern-Matching Must Be Initialized

**Problem**: If a struct defines a field but doesn't set a default, code that accesses it with `socket.__dala__.changed` will fail when the field is missing.

**Solution**: Always initialize all fields in the struct definition, not just in constructor functions.

**Reference**: Burned us in `Dala.Ui.Socket` where `:changed` was only set in `new/2`.

### 15. Multi-Repo Changes Batch Together

**Problem**: A user-visible fix in dala often needs matching changes in dala_dev (build) and dala_new (template). Bumping versions without coordination produces ghost regressions.

**Rule**: Check all three repos before declaring done.

### 16. Dala Module Restructuring (Facade Pattern)

**Problem**: Dala's internal modules were restructured into sub-namespaces (e.g., `Dala.Renderer` → `Dala.Ui.Renderer`, `Dala.Socket` → `Dala.Ui.Socket`, `Dala.NativeLogger` → `Dala.Platform.NativeLogger`).

**Solution**: Top-level facade modules still exist and delegate to the new locations. Use the **facade module names** (`Dala.Screen`, `Dala.Socket`, `Dala.Renderer`, etc.) for public API calls — they still work. Use the **new sub-namespace paths** when referencing internal implementation details.

**Key mappings**:
- `Dala` — main facade (`lib/dala.ex`), delegates `assign/2` and `assign/3` to `Dala.Socket`
- `Dala.App` — app facade (`lib/dala/app.ex`), delegates to `Dala.App.App` (`lib/dala/app/app.ex`)
- `Dala.Screen` — screen facade (`lib/dala/screen.ex`), delegates to `Dala.Screen.Screen` (`lib/dala/screen/screen.ex`)
- `Dala.Socket` — socket struct + API (`lib/dala/socket.ex`); `Dala.Ui.Socket` is a deprecated type alias
- `Dala.Renderer` — renderer facade (`lib/dala/renderer.ex`), delegates to `Dala.Ui.Renderer` (`lib/dala/ui/renderer.ex`)
- `Dala.Node` — node struct (`lib/dala/node.ex`), includes `stable_id/1`, `init_id_cache/0`, `compute_layout_hash/1`, `from_map/2`, `to_map/1`
- `Dala.Test` — testing helpers (`lib/dala/test.ex`), implementation directly in the facade module (no `Dala.Test.Test` sub-module)
- `Dala.ML` — ML facade (`lib/dala/ml.ex`), implementation directly in the facade module (no `Dala.Ml.Ml` sub-module)
- `Dala.Component` → `Dala.Ui.NativeView`
- `Dala.ComponentServer` → `Dala.Ui.NativeView.Server`
- `Dala.ComponentRegistry` → `Dala.Ui.NativeView.Registry`
- `Dala.Diff` → `Dala.Ui.Diff`
- `Dala.List` → `Dala.Ui.List`
- `Dala.Style` → `Dala.Ui.Style`
- `Dala.Native` → `Dala.Platform.Native`
- `Dala.NativeLogger` → `Dala.Platform.NativeLogger`
- `Dala.Dist` → `Dala.Connectivity.Dist`
- `Dala.WiFi` → `Dala.Connectivity.Wifi`
- `Dala.Device` → `Dala.Device.Device` (with `Dala.Device.Ios` and `Dala.Device.Android` as sub-modules)
- `Dala.Bluetooth` → `Dala.Hardware.Bluetooth`
- `Dala.Haptic` → `Dala.Hardware.Haptic`
- `Dala.Scanner` → `Dala.Hardware.Scanner`
- `Dala.Biometric` → `Dala.Hardware.Biometric`
- `Dala.NFC` → `Dala.Hardware.Nfc` (new)
- `Dala.Camera` → `Dala.Media.Camera`
- `Dala.Audio` → `Dala.Media.Audio`
- `Dala.Photos` → `Dala.Media.Photos`
- `Dala.PubSub` → `Dala.Platform.PubSub`
- `Dala.Event` → `Dala.Event.Event`
- `Dala.LiveView` → `Dala.Platform.LiveView`
- `Dala.WebView` → `Dala.Ui.Embedded.Webview`
- `Dala.Motion` → `Dala.Ui.Sensor.Motion`
- `Dala.Alert` → `Dala.Ui.Feedback.Alert`
- `Dala.Theme.set/1` → `Dala.Theme.Theme.set/1`
- `Dala.Plugin` → `Dala.Plugin` (struct + behaviour, unchanged)
- `Dala.Plugin.Registry` → `Dala.Plugin.Registry` (unchanged)
- `Dala.Plugin.Lifecycle` → `Dala.Plugin.Lifecycle` (unchanged)
- `Dala.Plugin.Component` → `Dala.Plugin.Component` (unchanged)
- `Dala.Plugin.ComponentDSL` → `Dala.Plugin.ComponentDSL` (unchanged)
- `Dala.Plugin.Manifest` → `Dala.Plugin.Manifest` (unchanged)
- `Dala.Plugin.Protocol` → `Dala.Plugin.Protocol` (unchanged)
- `Dala.Plugin.Event` → `Dala.Plugin.Event` (new — typed event definitions for plugins)
- `Dala.Nav.Registry` → `Dala.Nav.Registry` (unchanged)
- `Dala.Screen.Manager` → `Dala.Screen.Manager` (new — central registry for tracking active screens)
- `Dala.Preview` → `Dala.Designer` (dev-only, in `dev_tools/`, renamed in v0.8.0)
- `Dala.Wakelock` → `Dala.Hardware.Wakelock`
- `Dala.Storage` → `Dala.Storage.Storage`
- `Dala.Blob` → `Dala.Storage.Blob`
- `Dala.Files` → `Dala.Storage.Files`
- `Dala.Settings` → `Dala.Platform.Settings`
- `Dala.State` → `Dala.Platform.State`
- `Dala.Linking` → `Dala.Platform.Linking`
- `Dala.Background` → `Dala.Platform.Background`
- `Dala.Gpu` → `Dala.Gpu` (GPU surface rendering, unchanged)
- `Dala.Permissions` → `Dala.Permissions` (permission management, unchanged)
- `Dala.Clipboard` → `Dala.Platform.Clipboard`
- `Dala.Share` → `Dala.Platform.Share`
- `Dala.Location` → `Dala.Platform.Location`
- `Dala.Notify` → `Dala.Platform.Notify`
- `Dala.Video` → `Dala.Media.Video`
- `Dala.Setup` → `Dala.Setup` (BT/WiFi setup helper, unchanged; `Dala.Setup.Android` and `Dala.Setup.Ios` are new platform-specific sub-modules)

**New in v0.8.0**:
- `Dala.Spark.DslVerifier` — Compile-time DSL verification (`lib/dala/spark/dsl_verifier.ex`)
- `Dala.Spark.DslCompileHook` — `@before_compile` hook for DSL verification (`lib/dala/spark/dsl_compile_hook.ex`)
- `Dala.Setup.Android` — Android BT/WiFi setup automation (`lib/dala/setup/android.ex`)
- `Dala.Setup.Ios` — iOS BT/WiFi setup automation (`lib/dala/setup/ios.ex`)
- `Dala.Designer` — Renamed from `Dala.Preview` (`dev_tools/dala/preview.ex`)

**New facade modules** (top-level, delegate to sub-namespaces):
- `Dala` — main facade, delegates `assign/2` and `assign/3` to `Dala.Socket`
- `Dala.ML` — ML facade, implementation directly in the facade module (no `Dala.Ml.Ml` sub-module)
- `Dala.Test` — testing facade, implementation directly in the facade module (no `Dala.Test.Test` sub-module)
- `Dala.App` — app facade, delegates to `Dala.App.App` (implementation at `lib/dala/app/app.ex`)
- `Dala.Screen` — screen facade, delegates to `Dala.Screen.Screen` (implementation at `lib/dala/screen/screen.ex`)
- `Dala.Renderer` — renderer facade, delegates to `Dala.Ui.Renderer`
- `Dala.Plugin` — plugin facade, delegates to `Dala.Plugin` (struct + behaviour, unchanged)
- `Dala.Component` — component facade (`lib/dala/component.ex`), delegates to `Dala.Ui.NativeView`
- `Dala.ComponentServer` — component server facade (`lib/dala/component_server.ex`), delegates to `Dala.Ui.NativeView.Server`
- `Dala.ComponentRegistry` — component registry facade (`lib/dala/component_registry.ex`), delegates to `Dala.Ui.NativeView.Registry`
- `Dala.Diff` — diff engine facade (`lib/dala/diff.ex`), delegates to `Dala.Ui.Diff`
- `Dala.List` — list rendering facade (`lib/dala/list.ex`), delegates to `Dala.Ui.List`
- `Dala.Event` — unified event facade (`lib/dala/event.ex`), delegates to `Dala.Event.Event`
- `Dala.PubSub` — PubSub facade (`lib/dala/pubsub.ex`), delegates to `Dala.Platform.PubSub`
- `Dala.Native` — platform-native NIF fallback implementations (`lib/dala/native.ex`), provides fallback implementations for CoreML and ONNX NIF functions that return `:not_supported` on non-mobile platforms

**Rule**: When writing new code in dala_dev that references dala internals, use the new sub-namespace paths. When generating code for user projects (templates), use the facade names.

### 17. UI Render Path: Binary Protocol

**Problem**: The render pipeline now uses a custom binary protocol instead of JSON.

**Architecture**: `Dala.Ui.Renderer.render/4` encodes `Dala.Node` trees to compact binary → `Dala.Platform.Native.set_root_binary/1` NIF receives binary data.

**Binary format**: `[0xDA][0xA1][u16 version=3][u16 flags][u64 node_count] + nodes`
**Patches**: `[0xDA][0xA1][u16 version=3][u16 patch_count] + [FRAME_BEGIN][opcodes...][FRAME_END]`

**Zero-copy**: Rustler's `Binary<'a>` maps directly to BEAM off-heap binaries.

### 18. Skip Renders When Nothing Changed

**Problem**: Unnecessary renders waste CPU and cause flicker.

**Solution**: `Dala.Ui.Socket.assign/3` tracks changed keys in `__dala__.changed`. `Dala.Screen.Screen.do_render/3` skips the render if no assigns changed and no navigation occurred. `do_render/3` clears `changed` even when skipping render, preventing stale change tracking.

### 19. Incremental Rendering with Diff Engine

**Problem**: Full tree re-renders are expensive.

**Solution**: `Dala.Ui.Diff.diff/2` compares two `Dala.Node` trees and produces patches (`:replace`, `:update_props`, `:insert`, `:remove`). `Dala.Ui.Renderer.render_patches/5` sends only patches to native when supported. Falls back to full render if native doesn't support `apply_patches/1`.

### 20. Spark DSL for Declarative Screens

**Problem**: Writing `render/1` by hand is verbose.

**Solution**: `use Dala.Spark.Dsl` provides a declarative DSL that mirrors `Dala.Ui.Widgets` one-to-one. Features `@ref` syntax for assigns, auto-generated `mount/3`, and compile-time verifiers.

### 21. Zero-Config ML on iOS/Android

**Problem**: ML configuration is platform-specific and error-prone.

**Solution**: `Dala.ML.setup/0` auto-configures the ML stack:
- iOS device: EMLX with Metal GPU, JIT disabled (W^X policy)
- iOS simulator: EMLX with Metal GPU, JIT enabled
- Android: Nx.BinaryBackend

CoreML predictions are synchronous (NIF captures ObjC callback via Mutex) and run on the dirty CPU scheduler (`schedule = "DirtyCpu"`).
ONNX NIFs are also dirty CPU scheduled and available on both iOS and Android.

### 22. Bluetooth/WiFi Setup

**Problem**: Bluetooth and WiFi permissions setup is platform-specific and tedious.

**Solution**: Runtime helpers: `Dala.Setup.check_bluetooth/0`, `Dala.Setup.check_wifi/0`, `Dala.Setup.diagnostic/0`.

### 23. Plugin Lifecycle and Capability Registration

**Problem**: Plugins need a structured lifecycle with dependency ordering and capability negotiation.

**Solution**: `Dala.Plugin` behaviour with `Dala.Plugin.Lifecycle` and `Dala.Plugin.Registry`:
- Lifecycle states: `:registered` → `:initialized` → `:active` → `:registered` → `:unloaded`
- `Dala.Plugin.Lifecycle` manages init/activate/deactivate/cleanup transitions
- `Dala.Plugin.Registry` handles dependency resolution (topological sort via Kahn's algorithm), capability queries, and platform filtering
- Two DSL styles: top-level declarations and `plugin do` block
- Plugins MUST declare `schema_version`, `protocol_version`, and `native_api_version`
- `Dala.Plugin.Event` provides typed event definitions with compile-time field validation and binary encoding
- Plugin macros: `component/2`, `schema_version/1`, `protocol_version/1`, `native_api_version/1`, `description/1`, `permission/1`, `dependency/1`, `platform/1`, `native_module/1`, `plugin/1` (block), `plugin_component/2`, `plugin_event/2`, `plugin_native/2`, `plugin_permission/1`, `plugin_dependency/2`, `plugin_platform/1`, `plugin_description/1`
- Generated functions: `__plugin_info__/0`, `register/0`, `component/1`, `components/0`, `components_list/0`, `capabilities/0`, `permissions/0`, `native_modules/1`, `dependencies/0`, `validate_config/1`, `handle_event/3`, `init/1`, `cleanup/1`, `generate_protocol/0`, `generate_manifest/0`, `__auto_register__/0`
- `Dala.Plugin.auto_register/0` scans all loaded applications for plugin modules and auto-registers them

**Rule**: Plugins should NEVER directly access BEAM internals, scheduler state, or raw protocol sockets. Use the Host API seam.

### 24. Dev-Only UI Preview and Design Tool

**Problem**: Developers need to preview UI without a device.

**Solution**: `Dala.Designer` (in `dev_tools/`) provides:
- Static preview — generates standalone HTML with CSS that mimics Dala's styling
- Live designer — Phoenix LiveView server with drag-and-drop component palette, property editor, live phone-frame preview, and code generation

**Key points**:
- Lives in `dev_tools/` — only compiled in `:dev` environment
- Not included in Hex package
- Code generation supports Spark DSL style

### 25. WebView Interact API

**Problem**: Programmatic control of WebView content from Elixir is needed for production use and testing.

**Solution**: `Dala.Ui.Embedded.Webview.interact/2` provides a high-level API:
- `{:tap, selector}`, `{:type, selector, text}`, `{:clear, selector}`, `{:eval, js_code}`, `{:scroll, selector, dx, dy}`, `{:wait, selector, timeout_ms}`
- Also: `navigate/2`, `reload/1`, `stop_loading/1`, `go_forward/1`
- Results arrive via `handle_info({:webview, :interact_result, ...})` and `handle_info({:webview, :eval_result, ...})`

### 26. Event System and Platform APIs

**Problem**: Unified event routing between native and BEAM, plus platform-specific APIs.

**Solution**:
- `Dala.Event` — unified event emission: `dispatch/4`, `emit/4`, `send_test/6`
- `Dala.Event.Bridge` — event routing between native and BEAM
- `Dala.Event.Throttle` — event throttling/debouncing
- `Dala.Event.Trace` — event tracing for debugging
- `Dala.Event.Target` — event target
- `Dala.Event.Address` — event addressing
- `Dala.Event.Component` — component-level events
- `Dala.Ui.NativeView` — stateful Elixir processes paired with platform-native views
- `Dala.Platform.Background` — background execution keep-alive
- `Dala.Platform.Linking` — open URLs, deep links
- `Dala.Platform.Settings` — persistent settings (UserDefaults/SharedPreferences)
- `Dala.Platform.State` — DETS-backed persistent key-value store
- `Dala.Platform.PubSub` — local PubSub via Elixir Registry
- `Dala.Platform.Registry` — process registry
- `Dala.Platform.Clipboard` — clipboard
- `Dala.Platform.Share` — share sheet
- `Dala.Platform.Location` — location services
- `Dala.Platform.Notify` — push notifications
- `Dala.Platform.Diag` — diagnostics
- `Dala.Storage.Blob` — binary data via native blob references
- `Dala.Storage.Storage` — app-local file storage with named locations
- `Dala.Wakelock` — screen wakelock
- `Dala.Ui.Feedback.Alert` — native alerts, action sheets, toasts
- `Dala.Ui.Embedded.Webview` — bidirectional JS bridge for WebView
- `Dala.Ui.Sensor.Motion` — accelerometer and gyroscope
- `Dala.List` — list rendering with custom item renderers
- `Dala.Connectivity.Dist` — platform-aware Erlang distribution startup
- `Dala.Setup` — BT/WiFi setup helper

### 27. Dala.Test — Two-Layer Inspection Model

**Problem**: Testing Dala apps requires both logical render tree inspection and native UI verification.

**Solution**: `Dala.Test` exposes two complementary views:
- **Render tree** (`tree/1`, `find/2`) — Dala logical components, fast, exact, has `on_tap` tags
- **Native view tree** (`view_tree/1`, `find_view/2`) — native UIView/View hierarchies via NIF
- **Accessibility tree** (`ui_tree/1`) — OS accessibility tree (requires AX activation on iOS)

**Navigation helpers** (synchronous): `pop/1`, `navigate/3`, `pop_to/2`, `pop_to_root/1`, `reset_to/3`
**Interaction helpers**: `tap/2` (by tag), `back/1` (system back), `select/3` (list row)
**Native UI helpers**: `tap_xy/3`, `type_text/2`, `swipe/5`, `ax_action/3`, `ax_action_at_xy/4`, `toggle/2`, `adjust_slider/4`, `dismiss_alert/2`, `long_press_xy/4`, `delete_backward/1`, `key_press/2`, `clear_text/1`
**WebView helpers**: `webview_eval/2`, `webview_tap/3`, `webview_type/3`, `webview_navigate/2`, `webview_reload/1`, `webview_stop_loading/1`, `webview_go_forward/1`, `webview_clear/2`, `webview_screenshot/1`, `webview_post_message/2`
**Inspection helpers**: `screen/1`, `assigns/1`, `inspect/1`, `screen_info/1`, `view_tree_flat/1`, `flatten_tree/1`, `find_native/2`, `wait_for/3`, `wait_for_text/3`
**Simulation helpers**: `send_message/2` — simulates async device API results (camera, location, notifications, permissions, etc.)
**Native gesture helpers**: `tap_native/1`, `locate/1` — drive native UI via `idb` on iOS simulator

**Rule**: Prefer `Dala.Test` over screenshots. Use render tree first for Dala apps, native tree for geometry/frames, AX tree for non-Dala content.

### 28. Dala.App screens/1 Helper

**Problem**: Screen modules need compile-time validation in navigation declarations.

**Solution**: Use `screens/1` in your app's `navigation/1` to register screen modules:
```elixir
def navigation(_) do
  screens([MyApp.HomeScreen, MyApp.SettingsScreen])
  stack(:home, root: MyApp.HomeScreen)
end
```
This validates at compile time that the modules are valid `Dala.Screen` modules.

### 29. GPU Render Surface

**Problem**: GPU rendering requires a surface lifecycle managed by a GenServer.

**Solution**: `Dala.Gpu` provides a CPU-side framebuffer uploaded to GPU every frame:
- `Dala.Gpu.create_surface/2` — creates a new GPU surface
- `Dala.Gpu.clear/2`, `Dala.Gpu.fill_rect/6`, `Dala.Gpu.draw_line/6` — render commands
- `Dala.Gpu.present/1` — flush command queue and update GPU texture
- `Dala.Gpu.dispatch_compute/4` — dispatch GPU compute shaders
- `Dala.Gpu.with_pixels/2` — direct pixel access via callback

**Sub-modules**: `Dala.Gpu.Command` (render commands), `Dala.Gpu.Surface` (GenServer), `Dala.Gpu.Compute` (compute shaders), `Dala.Gpu.Compute.Buffer` (compute buffer), `Dala.Gpu.Compute.Kernel` (compute kernel), `Dala.Gpu.Compute.Pipeline` (compute pipeline), `Dala.Gpu.Native` (native GPU interface)

**Use cases**: Custom canvas rendering, ML tensor visualization, game-like rendering, video processing, shader effects.

### 30. Media Runtime (Video, Scene Graph, GPU Filters)

**Problem**: Media playback and processing requires a pipeline architecture.

**Solution**: Dala's media runtime provides:
- `Dala.Media.Video` — video playback
- `Dala.Media.Pipeline` — media pipeline
- `Dala.Media.Scene` — scene graph
- `Dala.Media.Stream` — media streaming
- `Dala.Media.Filter` — GPU filters
- `Dala.Media.Texture` — GPU textures
- `Dala.Media.Adaptive` — adaptive bitrate
- `Dala.Media.Animation` — animations
- `Dala.Media.Clock` — media clock
- `Dala.Media.Subtitle` — subtitles

**Rule**: Media modules use the GPU surface for rendering. See the Dala library's `guides/media_runtime.md` for the complete media runtime documentation.

### 32. File Transfer Between Dev Machine and Devices

**Problem**: Developers need to move files to/from devices — fixtures, configs, assets, logs, databases — without rebuilding the app.

**Solution**: `DalaDev.FileTransfer` provides four operations across all platforms:

- **`push/3`** — copies a local file or directory to the device. On Android, folders are staged as tar archives (avoids per-file adb overhead and preserves SELinux context). On iOS Simulator, files are written directly to the app's Documents directory on the host filesystem. On iOS Physical, `xcrun devicectl` handles the transfer.
- **`pull/3`** — copies a remote file or directory to the local machine. Uses the same tar staging approach on Android for directories.
- **`sync/3`** — bidirectional directory synchronization. Compares local and remote file trees by size and mtime, then pushes new/changed local files, pulls new/changed remote files, and optionally deletes remote files not present locally. Ideal for keeping fixture directories or asset folders in sync.
- **`ls/2`** — lists files in a remote directory.

All operations support `--on_conflict` (`overwrite`, `skip`, `rename`) and `--progress` flags.

**Gotcha — Android non-rooted pull**: Pulling files from a non-rooted device requires copying from the app sandbox to `/data/local/tmp/` via `run-as`, then `adb pull` from there. The staging file is cleaned up in an `after` block to avoid leaking temp files on the device.

**Gotcha — iOS Physical delete**: `xcrun devicectl` does not support deleting files from the app container. The `sync` delete action logs a warning on iOS Physical rather than failing silently.

### 33. Permission Management

**Problem**: iOS and Android require runtime permission requests for device capabilities.

**Solution**: `Dala.Permissions` provides a unified interface:
- `Dala.Permissions.request(pid, :camera)` — request a permission (result arrives via `handle_info`)
- `Dala.Permissions.check(:camera)` — check if granted (`:granted` | `:denied`)
- `Dala.Permissions.supported_permissions/0` — list all supported permissions
- `Dala.Permissions.ios_plist_key/1` — returns the iOS plist key for a permission
- `Dala.Permissions.android_permission/1` — returns the Android permission string

**Supported permissions**: `:camera`, `:microphone`, `:bluetooth`, `:location`, `:storage`, `:photos`, `:contacts`, `:notifications`, `:nfc`

**Rule**: Always request permissions before using the corresponding device API. Use `Dala.Permissions` rather than platform-specific permission code.

## Public API Seams (Testing Interfaces)

These functions are intentionally public to enable thorough testing. They serve as "seams" where we can inject test data and verify behavior in isolation.

**⚠️ Warning**: Do **NOT** make these functions private. They are public by design to support our testing strategy.

### Why These Are Public

Many of these functions contain parsing logic or platform-specific narrowing logic that needs to be tested independently of the full deployment pipeline. By keeping them public:
- We can test parsers with known input/output pairs
- We can test platform narrowing without needing actual devices
- We can verify error handling without triggering real deployments

### Discovery and Parsing

**Android device discovery**:
- `DalaDev.Discovery.Android.parse_devices_output/1` — Parses `adb devices -l` output

**iOS device/simulator discovery**:
- `DalaDev.Discovery.IOS.parse_simctl_json/1` — Parses `xcrun simctl list -j` JSON output
- `DalaDev.Discovery.IOS.parse_simctl_text/1` — Parses text output from simctl
- `DalaDev.Discovery.IOS.parse_runtime_version/1` — Extracts iOS runtime version info

### Build and Platform Logic

**Native build utilities**:
- `DalaDev.NativeBuild.narrow_platforms_for_device/2` — Determines which platforms to build for based on device
- `DalaDev.NativeBuild.ios_toolchain_available?/0` — Checks if iOS cross-compile toolchain is installed
- `DalaDev.NativeBuild.read_sdk_dir/1` — Reads SDK directory paths from configuration
- `DalaDev.NativeBuild.ios_build_targets/1` — Pure decision for `--all` fan-out: returns `[:physical | :sim]` targets from toolchain/sim-script/physical-UDID inputs
- `DalaDev.NativeBuild.__load_config_in__/1` — Like `__load_config__/0` but reads dala.exs from an explicit dir (test seam — avoids VM-global `File.cd!`)

### OTP Management

**OTP downloader**:
- `DalaDev.OtpDownloader.valid_otp_dir?/2` — Validates cached OTP tarballs against schema version
- `DalaDev.OtpDownloader.ios_device_extras_present?/1` — Checks for required iOS device extras in OTP

### Emulator Management

**Emulator utilities**:
- `DalaDev.Emulators.parse_simctl_json/1` — Parses simulator list JSON
- `DalaDev.Emulators.find_emulator_binary/1` — Locates emulator executables

### Provisioning and Diagnostics

**Error diagnosis**:
- `DalaDev.Provision.diagnose_xcodebuild_failure/1` — Translates xcodebuild errors into actionable hints

### Crash Analysis

**Crash dump utilities**:
- `DalaDev.CrashDump.parse/1` — Parses crash dump strings
- `DalaDev.CrashDump.parse_file/1` — Parses crash dump files
- `DalaDev.CrashDump.summary/1` — Generates crash dump summaries
- `DalaDev.CrashDump.html_report/1` — Generates HTML reports from crash dumps

### Device and Tunnel

**Device utilities**:
- `DalaDev.Device.short_id/1` — Generates short device ID
- `DalaDev.Device.node_name/1` — Generates node name from device
- `DalaDev.Device.summary/1` — Generates device summary

**Tunnel management**:
- `DalaDev.Tunnel.dist_port/1` — Gets distribution port for device

### Hot-Push

**Hot-push deployment**:
- `DalaDev.HotPush.snapshot_beams/0` — Snapshots current BEAM files
- `DalaDev.HotPush.push_changed/2` — Pushes only changed BEAM files

### File Transfer

**File transfer utilities**:
- `DalaDev.FileTransfer.push/3` — Push file or directory to devices
- `DalaDev.FileTransfer.pull/3` — Pull file or directory from device
- `DalaDev.FileTransfer.sync/3` — Bidirectional directory sync with delete support
- `DalaDev.FileTransfer.ls/2` — List files on device

### Configuration

**Config utilities**:
- `DalaDev.Config.bundle_id/0` — Resolves app bundle ID
- `DalaDev.Config.load_dala_config/0` — Reads dala.exs configuration
- `DalaDev.Config.load_dala_config_from/1` — Same, from an explicit project dir (test seam — avoids VM-global `File.cd!`)

**Connection**:
- `DalaDev.Connector.start_epmd/0` — Starts EPMD daemon (public for testing)
- `DalaDev.Connector.handle_dist_start/2` — Handles Node.start result (public for testing)

### Device Control Utilities

**App reset (pure command builders + dispatch)**:
- `DalaDev.AppReset.android_packages/1` — Packages to stop: project bundle id + `com.dala.<app>` wrapper, deduplicated
- `DalaDev.AppReset.android_stop_commands/2` — adb arg lists to force-stop packages and clear logcat
- `DalaDev.AppReset.android_clear_data_commands/2` — adb arg lists for `pm clear`
- `DalaDev.AppReset.ios_sim_commands/3` — simctl arg lists (terminate both bundles, optional uninstall)

**Device shell**:
- `DalaDev.DeviceShell.resolve_target/1` — Resolves a device ID into a shell target (`{:android, serial}` / `{:ios_simulator, udid}` / `{:ios_physical, udid}`)
- `DalaDev.DeviceShell.open_command/2`, `exec_command/3` — Pure command builders; return `{:shell | :dir | :exec, cmd}` or `:unsupported`

**Ports**:
- `DalaDev.Ports.port_map/1` — Expected port map (EPMD/dist/LV); takes a device-lister override (test seam)
- `DalaDev.Ports.liveview_port/0` — Hash-based LV port formula matching dala's allocation
- `DalaDev.Ports.listeners_on/1` — Host PIDs listening on a port (lsof)
- `DalaDev.Ports.kill_pids/1` — Kills host PIDs

**Deep links / clipboard / location (pure builders + dispatch)**:
- `DalaDev.DeepLink.valid_url?/1`, `android_open_command/2`, `ios_open_command/2`; `open_devices/3` dispatch seam (`opts[:exec]` overrides tagged `{:adb,args}`/`{:xcrun,args}` execution)
- `DalaDev.DeviceClipboard.ios_get_command/1`, `ios_put_command/2`; get/put accept `opts[:devices]` + `opts[:exec]`
- `DalaDev.LocationSpoof.parse_coords/1` — Validates/parses `<lat>,<lng>` with range checks
- `DalaDev.LocationSpoof.android_set_command/3` (longitude-first!), `ios_set_command/3`, `ios_clear_command/1`; set/clear accept `opts[:devices]` + `opts[:exec]`

**Environment snapshot**:
- `DalaDev.EnvSnapshot.collect/0`, `collect_json/0` — Full dev-environment inventory
- `DalaDev.EnvSnapshot.parse_adb_version/1` (both banner layouts), `parse_xcrun_version/1`, `parse_emulator_version/1` — Version extraction from tool output

**Screenshot baselines**:
- `DalaDev.ScreenBaseline.baseline_path/2`, `diff_path/2`, `device_dir/1` — Storage layout under `.dala/screenshots/<device>/`
- `DalaDev.ScreenBaseline.save/3`, `compare/3` — Capture-and-store / capture-and-compare (`opts[:capture]` overrides the capture call for tests)
- `DalaDev.ScreenBaseline.compare_bytes/2` — Pure byte comparison (`:match` | `{:changed, size_a, size_b}`)

**Emulator recipes**:
- `DalaDev.Emulators.recipes/0`, `recipe_args/1` — Named Android launch presets
- `Mix.Tasks.Dala.Emulators.split_flags/1` — Splits `--emulator_args` strings, keeping quoted runs together

**Task render seams** (thin tasks delegate rendering to these so tests don't need devices):
- `Mix.Tasks.Dala.Port.report/2`, `print_table/1`, `entry_json/1`, `kill_squatters/1`
- `Mix.Tasks.Dala.Reset.report/2` (results + JSON), `Mix.Tasks.Dala.Link.report/1`
- `Mix.Tasks.Dala.Env.print_summary/1`, `Mix.Tasks.Dala.Shell.handle_plan/4`

### Paths

**Path resolution**:
- `DalaDev.Paths.default_runtime_dir/0` — Default OTP runtime directory
- `DalaDev.Paths.ios_sim_runtime_dir/1` — iOS simulator runtime directory
- `DalaDev.Paths.project_uses_env_var_runtime?/1` — Checks if project uses env-var runtime path

### Utilities

**Shared utilities**:
- `DalaDev.Utils.compile_regex/2` — Centralized regex compilation
- `DalaDev.Utils.run_adb_with_timeout/2` — ADB command with timeout protection (runs `adb` directly with no shell, kills the process on timeout; works on macOS/Linux/Windows without GNU `timeout`; `opts[:exec]` overrides execution — test seam)
- `DalaDev.Utils.parse_adb_devices_output/1` — Parses ADB devices output
- `DalaDev.Utils.normalize_cli_args/1` — Rewrites underscored long flags (`--dry_run`) to hyphenated form before OptionParser; call at the top of every Mix task run/1

### Output and CLI Ergonomics

**Centralized output**:
- `DalaDev.Output.configure/1` — Sets `--quiet` / `--json` mode (call at top of each Mix task)
- `DalaDev.Output.step/2`, `info/1`, `success/1`, `warn/1`, `error/1`, `hint/1` — Semantic output helpers; use these instead of raw `IO.puts`
- `DalaDev.Output.timed/2` — Wraps a long operation, prints elapsed time
- `DalaDev.Output.format_elapsed/1`, `format_bytes/1` — Human-readable formatting

**Dev server dependency guard**:
- `DalaDev.ServerDeps.ensure_available!/0` — Raises with install hint when optional Phoenix deps are missing
- `DalaDev.ServerDeps.available?/0` — Checks if dev-server deps are loadable

**Deploy dry-run support**:
- `DalaDev.Deployer.collect_beam_dirs/0` — Public for `mix dala.deploy --dry-run`
- `DalaDev.Deployer.count_beams/1` — Public for `mix dala.deploy --dry-run`
- `DalaDev.HotPush.push_changed_detailed/2` — Like `push_changed/2` but also returns pushed module names (used by `mix dala.watch`)

### Terminal UI (TUI)

**TUI state and views**:
- `DalaDev.Tui.State.nav_items/1` — Returns navigation items for current tab
- `DalaDev.Tui.State.detail_items/1` — Returns detail items for current selection
- `DalaDev.Tui.State.handle_key/2` — Pure key handling (returns updated state)
- `DalaDev.Tui.Devices.list/0` — Lists all discovered devices with node metadata
- `DalaDev.Tui.Devices.display_name/1` — Formats device for display
- `DalaDev.Tui.Devices.status_icon/1` — Returns status icon for device
- `DalaDev.Tui.Devices.from_device/1` — Converts a `DalaDev.Device` struct into a TUI device entry (test seam)
- `DalaDev.Tui.Devices.summary/1` — Returns one-line device summary
- `DalaDev.Tui.Remote.query/1` — Queries a remote node for version/memory/screen
- `DalaDev.Tui.Remote.connected_nodes/0` — Lists connected distribution nodes
- `DalaDev.Tui.Remote.reachable?/1` — Checks if a node is reachable
- `DalaDev.Tui.Tasks.list/0` — Lists all available tasks
- `DalaDev.Tui.Tasks.by_category/1` — Filters tasks by category
- `DalaDev.Tui.Views.NavPanel.render/2` — Renders navigation panel
- `DalaDev.Tui.Views.DetailPanel.render/2` — Renders detail panel
- `DalaDev.Tui.Views.StatusBar.render/2` — Renders status bar
- `DalaDev.Tui.Views.HelpOverlay.render/1` — Renders help overlay

### Monitoring and Observability

**Cluster visualization**:
- `DalaDev.ClusterViz.topology/0` — Returns cluster topology
- `DalaDev.ClusterViz.health_dashboard/0` — Returns health dashboard data
- `DalaDev.ClusterViz.process_distribution/0` — Shows process distribution across nodes
- `DalaDev.ClusterViz.liveview_flow/0` — Traces LiveView message flows

**Remote node observer**:
- `DalaDev.Observer.observe/2` — Observes a remote node
- `DalaDev.Observer.system_info/2` — Gets system info from remote node
- `DalaDev.Observer.process_list/2` — Lists processes on remote node
- `DalaDev.Observer.ets_tables/2` — Lists ETS tables on remote node

### Performance Profiling

**Profiling utilities**:
- `DalaDev.Profiling.profile/3` — Runs a profiling session
- `DalaDev.Profiling.analyze/1` — Analyzes profiling results
- `DalaDev.Profiling.flame_graph/2` — Generates flame graphs
- `DalaDev.Profiling.profile_locally/3` — Profiles code locally

### CI and Testing

**CI testing utilities**:
- `DalaDev.CITesting.run_suite/2` — Runs a CI test suite
- `DalaDev.CITesting.run_with_provisioning/2` — Runs tests with device provisioning
- `DalaDev.CITesting.generate_ci_report/2` — Generates CI reports

**A/B testing**:
- `DalaDev.ABTesting.run/2` — Runs an A/B test
- `DalaDev.ABTesting.analyze/1` — Analyzes A/B test results
- `DalaDev.ABTesting.generate_report/2` — Generates A/B test reports

### Release Utilities

**Android release build**:
- `Mix.Tasks.Dala.Release.Android.format_size/1` — Formats file sizes for release notes

### Dala Runtime Reference

When writing new code in dala_dev that references dala internals, use the **new sub-namespace paths** (not the facade names). Key modules and their locations:

**Core**:
- `Dala` — main facade (`lib/dala.ex`), delegates `assign/2` and `assign/3` to `Dala.Socket`, and `verify_dsl/1` to `Dala.Spark.Dsl`
- `Dala.App` — app facade (`lib/dala/app.ex`), delegates to `Dala.App.App` (`lib/dala/app/app.ex`)
- `Dala.Screen` — screen facade (`lib/dala/screen.ex`), delegates to `Dala.Screen.Screen` (`lib/dala/screen/screen.ex`)
- `Dala.Socket` — socket struct + API (`lib/dala/socket.ex`); `Dala.Ui.Socket` is a deprecated type alias
- `Dala.Renderer` — renderer facade (`lib/dala/renderer.ex`), delegates to `Dala.Ui.Renderer` (`lib/dala/ui/renderer.ex`)
- `Dala.Node` — node struct (`lib/dala/node.ex`), includes `stable_id/1`, `init_id_cache/0`, `compute_layout_hash/1`, `from_map/2`, `to_map/1`
- `Dala.Test` — testing helpers (`lib/dala/test.ex`), implementation directly in the facade module (no `Dala.Test.Test` sub-module)
- `Dala.ML` — ML facade (`lib/dala/ml.ex`), implementation directly in the facade module (no `Dala.Ml.Ml` sub-module)
- `Dala.Component` — component facade (`lib/dala/component.ex`), delegates to `Dala.Ui.NativeView`
- `Dala.ComponentServer` — component server facade (`lib/dala/component_server.ex`), delegates to `Dala.Ui.NativeView.Server`
- `Dala.ComponentRegistry` — component registry facade (`lib/dala/component_registry.ex`), delegates to `Dala.Ui.NativeView.Registry`
- `Dala.Diff` — diff engine facade (`lib/dala/diff.ex`), delegates to `Dala.Ui.Diff`
- `Dala.List` — list rendering facade (`lib/dala/list.ex`), delegates to `Dala.Ui.List`
- `Dala.Event` — unified event facade (`lib/dala/event.ex`), delegates to `Dala.Event.Event`
- `Dala.PubSub` — PubSub facade (`lib/dala/pubsub.ex`), delegates to `Dala.Platform.PubSub`
- `Dala.Native` — platform-native NIF fallback implementations (`lib/dala/native.ex`), provides fallback implementations for CoreML and ONNX NIF functions that return `:not_supported` on non-mobile platforms

**UI**:
- `Dala.Ui.Widgets` — declarative UI components (`lib/dala/ui/widgets.ex`)
- `Dala.Ui.Diff` — diff engine (`lib/dala/ui/diff.ex`)
- `Dala.Ui.NativeView` — stateful native views (`lib/dala/ui/native_view.ex`)
- `Dala.Ui.NativeView.Server` — native view GenServer (`lib/dala/ui/native_view/server.ex`)
- `Dala.Ui.NativeView.Registry` — native view registry (`lib/dala/ui/native_view/registry.ex`)
- `Dala.Ui.Feedback.Alert` — native alerts (`lib/dala/ui/feedback/alert.ex`)
- `Dala.Ui.Embedded.Webview` — WebView bridge (`lib/dala/ui/embedded/webview.ex`)
- `Dala.Ui.Sensor.Motion` — motion sensors (`lib/dala/ui/sensor/motion.ex`)
- `Dala.Ui.List` — list rendering (`lib/dala/ui/list.ex`)
- `Dala.Ui.Style` — styling (`lib/dala/ui/style.ex`)
- `Dala.Ui.Renderer` — binary protocol renderer (`lib/dala/ui/renderer.ex`)
- `Dala.Ui.Component` — component registry (`lib/dala/ui/component.ex`)
- `Dala.Ui.Scan` — scan UI (`lib/dala/ui/scan.ex`)
- `Dala.Ui.GpuCanvas` — GPU canvas (`lib/dala/ui/gpu_canvas.ex`)

**Navigation**:
- `Dala.Nav.Registry` — navigation registry (`lib/dala/nav/registry.ex`)
- `Dala.Screen.Manager` — screen manager (`lib/dala/screen/manager.ex`)

**Device APIs**:
- `Dala.Hardware.Bluetooth` — BLE (`lib/dala/hardware/bluetooth.ex`)
- `Dala.Hardware.Haptic` — haptics (`lib/dala/hardware/haptic.ex`)
- `Dala.Hardware.Scanner` — barcode/QR scanner (`lib/dala/hardware/scanner.ex`)
- `Dala.Hardware.Biometric` — biometrics (`lib/dala/hardware/biometric.ex`)
- `Dala.Hardware.Wakelock` — screen wakelock (`lib/dala/hardware/wakelock.ex`)
- `Dala.Hardware.Nfc` — NFC (`lib/dala/hardware/nfc.ex`)
- `Dala.Media.Camera` — camera (`lib/dala/media/camera.ex`)
- `Dala.Media.Audio` — audio (`lib/dala/media/audio.ex`)
- `Dala.Media.Photos` — photo library (`lib/dala/media/photos.ex`)
- `Dala.Media.Video` — video playback (`lib/dala/media/video.ex`)
- `Dala.Media.Pipeline` — media pipeline (`lib/dala/media/pipeline.ex`)
- `Dala.Media.Scene` — scene graph (`lib/dala/media/scene.ex`)
- `Dala.Media.Stream` — media streaming (`lib/dala/media/stream.ex`)
- `Dala.Media.Filter` — GPU filters (`lib/dala/media/filter.ex`)
- `Dala.Media.Texture` — GPU textures (`lib/dala/media/texture.ex`)
- `Dala.Media.Adaptive` — adaptive bitrate (`lib/dala/media/adaptive.ex`)
- `Dala.Media.Animation` — animations (`lib/dala/media/animation.ex`)
- `Dala.Media.Clock` — media clock (`lib/dala/media/clock.ex`)
- `Dala.Media.Subtitle` — subtitles (`lib/dala/media/subtitle.ex`)
- `Dala.Media.Gpu.Processor` — GPU media processor (`lib/dala/media/gpu/processor.ex`)
- `Dala.Connectivity.Dist` — Erlang distribution (`lib/dala/connectivity/dist.ex`)
- `Dala.Connectivity.Wifi` — WiFi (`lib/dala/connectivity/wifi.ex`)
- `Dala.Permissions` — permission management (`lib/dala/permissions.ex`)
- `Dala.Platform.Clipboard` — clipboard (`lib/dala/platform/clipboard.ex`)
- `Dala.Platform.Share` — share sheet (`lib/dala/platform/share.ex`)
- `Dala.Platform.Location` — location services (`lib/dala/platform/location.ex`)
- `Dala.Platform.Notify` — push notifications (`lib/dala/platform/notify.ex`)
- `Dala.Platform.Diag` — diagnostics (`lib/dala/platform/diag.ex`)
- `Dala.Platform.PubSub` — local PubSub (`lib/dala/platform/pub_sub.ex`)
- `Dala.Platform.Registry` — process registry (`lib/dala/platform/registry.ex`)
- `Dala.Setup` — BT/WiFi setup helper (`lib/dala/setup.ex`)
- `Dala.Setup.Android` — Android BT/WiFi setup (`lib/dala/setup/android.ex`)
- `Dala.Setup.Ios` — iOS BT/WiFi setup (`lib/dala/setup/ios.ex`)

**Platform**:
- `Dala.Platform.Native` — NIF interface (`lib/dala/platform/native.ex`)
- `Dala.Platform.NativeLogger` — native logging (`lib/dala/platform/native_logger.ex`)
- `Dala.Platform.Background` — background execution (`lib/dala/platform/background.ex`)
- `Dala.Platform.Linking` — deep linking (`lib/dala/platform/linking.ex`)
- `Dala.Platform.Settings` — persistent settings (`lib/dala/platform/settings.ex`)
- `Dala.Platform.State` — DETS-backed state (`lib/dala/platform/state.ex`)
- `Dala.Platform.PubSub` — local PubSub (`lib/dala/platform/pub_sub.ex`)
- `Dala.Platform.Registry` — process registry (`lib/dala/platform/registry.ex`)
- `Dala.Platform.Clipboard` — clipboard (`lib/dala/platform/clipboard.ex`)
- `Dala.Platform.Share` — share sheet (`lib/dala/platform/share.ex`)
- `Dala.Platform.Location` — location services (`lib/dala/platform/location.ex`)
- `Dala.Platform.Notify` — push notifications (`lib/dala/platform/notify.ex`)
- `Dala.Platform.Diag` — diagnostics (`lib/dala/platform/diag.ex`)
- `Dala.Platform.Permissions` — permissions (`lib/dala/platform/permissions.ex`)
- `Dala.Platform.LiveView` — LiveView support (`lib/dala/platform/live_view.ex`)

**Storage**:
- `Dala.Storage.Storage` — file storage (`lib/dala/storage/storage.ex`)
- `Dala.Storage.Blob` — binary blobs (`lib/dala/storage/blob.ex`)
- `Dala.Storage.Files` — file operations (`lib/dala/storage/files.ex`)
- `Dala.Storage.Android` — Android storage (`lib/dala/storage/android.ex`)
- `Dala.Storage.Apple` — Apple storage (`lib/dala/storage/apple.ex`)

**Events**:
- `Dala.Event.Event` — unified events (`lib/dala/event/event.ex`)
- `Dala.Event.Bridge` — event routing (`lib/dala/event/bridge.ex`)
- `Dala.Event.Throttle` — event throttling (`lib/dala/event/throttle.ex`)
- `Dala.Event.Trace` — event tracing for debugging (`lib/dala/event/trace.ex`)
- `Dala.Event.Target` — event target (`lib/dala/event/target.ex`)
- `Dala.Event.Address` — event addressing (`lib/dala/event/address.ex`)
- `Dala.Event.Component` — component-level events (`lib/dala/event/component.ex`)

**Testing**:
- `Dala.Test` — testing helpers, implementation directly at `lib/dala/test.ex` (no sub-module)

**Plugins**:
- `Dala.Plugin` — plugin behaviour + DSL (`lib/dala/plugin.ex`)
- `Dala.Plugin.Component` — component schema (`lib/dala/plugin/component.ex`)
- `Dala.Plugin.ComponentDSL` — component DSL (`lib/dala/plugin/component_dsl.ex`)
- `Dala.Plugin.Lifecycle` — lifecycle management (`lib/dala/plugin/lifecycle.ex`)
- `Dala.Plugin.Registry` — plugin registry (`lib/dala/plugin/registry.ex`)
- `Dala.Plugin.Protocol` — protocol generation (`lib/dala/plugin/protocol.ex`)
- `Dala.Plugin.Manifest` — manifest generation (`lib/dala/plugin/manifest.ex`)
- `Dala.Plugin.Event` — typed event definitions (`lib/dala/plugin/event.ex`)

**ML**:
- `Dala.ML` — ML facade (`lib/dala/ml.ex`), implementation directly in the facade module (no `Dala.Ml.Ml` sub-module)
- `Dala.ML.EMLX` — Apple Silicon GPU backend (`lib/dala/ml/emlx.ex`)
- `Dala.ML.CoreML` — iOS CoreML bridge (`lib/dala/ml/coreml.ex`)
- `Dala.ML.ONNX` — ONNX Runtime bridge (`lib/dala/ml/onnx.ex`)
- `Dala.ML.Gpu.Inference` — GPU ML inference (`lib/dala/ml/gpu/inference.ex`)
- `Dala.Ml.Nx` — Nx tensor helpers (`lib/dala/ml/nx.ex`)
- `Dala.Ml.Burn` — Burn ML framework (`lib/dala/ml/burn.ex`)
- `Dala.Ml.Burn.Serving` — Burn model serving (`lib/dala/ml/burn/serving.ex`)
- `Dala.Ml.Burn.Training` — Burn model training (`lib/dala/ml/burn/training.ex`)
- `Dala.Ml.ConfigHelper` — ML config helper (`lib/dala/ml/config_helper.ex`)
- `Dala.Ml.Debug` — ML debug utilities (`lib/dala/ml/debug.ex`)
- `Dala.Ml.Example` — ML examples (`lib/dala/ml/example.ex`)
- `Dala.Ml.Model` — ML model management (`lib/dala/ml/model.ex`)
- `Dala.Ml.Preprocess` — ML preprocessing (`lib/dala/ml/preprocess.ex`)
- `Dala.ML.Training` — ML training (`lib/dala/ml/training.ex`)

**GPU**:
- `Dala.Gpu` — GPU surface rendering (`lib/dala/gpu.ex`)
- `Dala.Gpu.Command` — GPU render commands (`lib/dala/gpu/command.ex`)
- `Dala.Gpu.Surface` — GPU surface GenServer (`lib/dala/gpu/surface.ex`)
- `Dala.Gpu.Compute` — GPU compute shaders (`lib/dala/gpu/compute.ex`)
- `Dala.Gpu.Compute.Buffer` — GPU compute buffer (`lib/dala/gpu/compute/buffer.ex`)
- `Dala.Gpu.Compute.Kernel` — GPU compute kernel (`lib/dala/gpu/compute/kernel.ex`)
- `Dala.Gpu.Compute.Pipeline` — GPU compute pipeline (`lib/dala/gpu/compute/pipeline.ex`)
- `Dala.Gpu.Native` — native GPU interface (`lib/dala/gpu/native.ex`)
- `native/dala_gpu/` — Rust GPU render backend

**Spark DSL**:
- `Dala.Spark.Dsl` — screen DSL (`lib/dala/spark/dsl.ex`)
- `Dala.Spark.Dsl.Entities` — Spark DSL entities (`lib/dala/spark/dsl/entities.ex`)
- `Dala.Spark.Dsl.ScreenHelper` — Spark DSL screen helper (`lib/dala/spark/dsl/screen_helper.ex`)
- `Dala.Spark.DslVerifier` — Compile-time DSL verification (`lib/dala/spark/dsl_verifier.ex`)
- `Dala.Spark.DslCompileHook` — `@before_compile` hook for DSL verification (`lib/dala/spark/dsl_compile_hook.ex`)
- `Dala.Spark.PubSub` — Spark PubSub (`lib/dala/spark/pubsub.ex`)
- `Dala.Spark.Transformers.GenerateMount` — Spark mount generator transformer (`lib/dala/spark/transformers/generate_mount.ex`)
- `Dala.Spark.Transformers.PubSub` — Spark PubSub transformer (`lib/dala/spark/transformers/pubsub.ex`)
- `Dala.Spark.Transformers.Render` — Spark render transformer (`lib/dala/spark/transformers/render.ex`)

**Theme**:
- `Dala.Theme` — theme facade (`lib/dala/theme.ex`)
- `Dala.Theme.Obsidian` — dark violet theme (`lib/dala/theme/obsidian.ex`)
- `Dala.Theme.Citrus` — warm charcoal + lime theme (`lib/dala/theme/citrus.ex`)
- `Dala.Theme.Birch` — warm parchment theme (`lib/dala/theme/birch.ex`)
- `Dala.Theme.Dark` — dark theme (`lib/dala/theme/dark.ex`)
- `Dala.Theme.Light` — light theme (`lib/dala/theme/light.ex`)
- `Dala.Theme.Adaptive` — adaptive theme (`lib/dala/theme/adaptive.ex`)
- `Dala.Theme.AdaptiveWatcher` — adaptive theme watcher (`lib/dala/theme/adaptive_watcher.ex`)

**Dev-only**:
- `Dala.Designer` — UI preview/designer, renamed from `Dala.Preview` in v0.8.0 (`dev_tools/dala/preview.ex`)

---

### 34. TUI Rendering Requires `ex_ratatui` Dependency

**Problem**: The TUI modules use `ExRatatui` structs (`%Block{}`, `%Paragraph{}`, `%Span{}`, etc.) which are only available when `ex_ratatui` is installed.

**Solution**: The TUI is included in `mix.exs` as a dependency. If you're developing the TUI without `ex_ratatui` in your dev environment, you'll get struct errors. Always run `mix deps.get` after pulling changes.

**Rule**: The TUI modules are compiled in all environments. If you want to make the TUI optional (dev-only), wrap it in a conditional compilation block or move it to `dev_tools/`.

### 35. Phoenix Dev-Server Deps Are Optional

**Problem**: `phoenix_live_view`, `bandit`, `phoenix_pubsub`, and `plug_crypto` are optional dependencies. CLI-only users shouldn't pull the Phoenix stack, but `mix dala.server` / `mix dala.web` need them.

**Solution**: Server tasks call `DalaDev.ServerDeps.ensure_available!/0` before starting, which raises with an install hint instead of a cryptic module-not-found error.

**Rule**: Any new task that touches Phoenix/Bandit must call `ensure_available!/0` first. Don't reference Phoenix modules at compile time outside `lib/dala_dev/server/`.

### 36. Use `DalaDev.Output` for All User-Facing Output

**Problem**: Raw `IO.puts` with inline ANSI codes is inconsistent, untestable, and can't be suppressed.

**Solution**: `DalaDev.Output` provides semantic helpers (`step/2`, `info/1`, `success/1`, `warn/1`, `error/1`, `hint/1`) plus `--quiet`/`--json` modes via `configure/1`.

**Rule**: Each Mix task calls `DalaDev.Output.configure(quiet: opts[:quiet], json: opts[:json])` at the top. Never use raw `IO.puts` for user-facing messages in `lib/dala_dev/` modules.

### 37. OptionParser Silently Drops Underscored Long Flags

**Problem**: Current Elixir releases only recognize hyphenated long options (`--dry-run`). Passing a documented underscored flag like `--dry_run`, `--on_conflict`, or `--beam_flags` is **silently ignored**: the token is swallowed, its value becomes a positional arg, and no invalid-option entry is reported. Safety-relevant flags (e.g. `push_file --on_conflict skip|rename`) were being dropped without any error.

**Solution**: Every Mix task that parses options calls `DalaDev.Utils.normalize_cli_args(args)` as the first statement of `run/1`. It rewrites `--flag_name` and `--flag_name=value` tokens to hyphenated form so both spellings parse identically; values are never touched.

**Rule**: New Mix tasks must normalize argv before `OptionParser.parse/2`. Declare switches with underscore keys (OptionParser normalizes parsed keys back to underscores), keep usage strings showing the underscore spelling users know, and add a regression test that passes the underscore flag through `run/1`.

**Remember**: If you make any of these private, every downstream test breaks loudly. But worse, you'll lose the ability to evolve the parsers safely through refactoring with test coverage.

## Key Files and Their Purposes

### Core Modules

**Device management**:
- `lib/dala_dev/device.ex` — Device struct definition + `node_name/1`, `short_id/1`, `summary/1`
- `lib/dala_dev/tunnel.ex` — ADB tunnel setup for device communication, `dist_port/1`
- `lib/dala_dev/connector.ex` — Discovery → tunnel → restart → wait → connect workflow
- `lib/dala_dev/config.ex` — Configuration handling (dala.exs), bundle ID resolution
- `lib/dala_dev/paths.ex` — Path resolution for OTP runtimes, SDKs, and build artifacts
- `lib/dala_dev/utils.ex` — Centralized utilities (regex compilation, ADB helpers, format_bytes)
- `lib/dala_dev/error.ex` — Standardized error handling and formatting

**Deployment**:
- `lib/dala_dev/deployer.ex` — Full BEAM push + app restart pipeline
- `lib/dala_dev/hot_push.ex` — BEAM snapshot + RPC push for hot code reloading
- `lib/dala_dev/native_build.ex` — APK/.app bundle building and signing
- `lib/dala_dev/otp_downloader.ex` — Pre-built OTP runtime downloads and caching

**Discovery**:
- `lib/dala_dev/discovery/android.ex` — ADB device discovery and parsing
- `lib/dala_dev/discovery/ios.ex` — xcrun simctl discovery and parsing

**Observability**:
- `lib/dala_dev/crash_dump.ex` — Crash dump parsing and HTML reports
- `lib/dala_dev/debugger.ex` — Interactive remote debugging
- `lib/dala_dev/observer.ex` — Web-based :observer for remote nodes
- `lib/dala_dev/tracing.ex` — Distributed tracing infrastructure
- `lib/dala_dev/profiling.ex` — Profiling and flame graph generation
- `lib/dala_dev/log_collector.ex` — Log collection and streaming
- `lib/dala_dev/screen_capture.ex` — Screenshot and video capture
- `lib/dala_dev/network.ex` — Network diagnostics
- `lib/dala_dev/network_diag.ex` — Network diagnostic utilities

**Terminal UI (TUI)**:
- `lib/dala_dev/tui.ex` — TUI public API and entry point
- `lib/dala_dev/tui/app.ex` — ExRatatui app callback
- `lib/dala_dev/tui/state.ex` — Pure navigation state and key handling
- `lib/dala_dev/tui/devices.ex` — Device discovery with node/dist port metadata
- `lib/dala_dev/tui/remote.ex` — Remote node queries (version, screen, memory, latency)
- `lib/dala_dev/tui/tasks.ex` — Mix task definitions for TUI
- `lib/dala_dev/tui/theme.ex` — Color palette and styles
- `lib/dala_dev/tui/views/nav_panel.ex` — Left panel rendering
- `lib/dala_dev/tui/views/detail_panel.ex` — Right panel rendering
- `lib/dala_dev/tui/views/status_bar.ex` — Status bar with version/connection info
- `lib/dala_dev/tui/views/help_overlay.ex` — Help overlay rendering

**Other**:
- `lib/dala_dev/emulators.ex` — Emulator lifecycle management (incl. named launch recipes)
- `lib/dala_dev/qr.ex` — QR code generation
- `lib/dala_dev/release.ex` — Release build utilities
- `lib/dala_dev/icon_generator.ex` — Icon generation for Android/iOS
- `lib/dala_dev/enable.ex` — Feature enablement
- `lib/dala_dev/benchmark.ex` — Performance benchmarking

**Battery benchmarking**:
- `lib/dala_dev/bench/device_observer.ex` — Subscribes to Dala.Device.Device events for ground-truth screen/app state
- `lib/dala_dev/bench/probe.ex` — Device state snapshot (screen, app, memory, battery)
- `lib/dala_dev/bench/preflight.ex` — Pre-flight checks before benchmark runs
- `lib/dala_dev/bench/reconnector.ex` — Automatic node reconnection during long-running benches
- `lib/dala_dev/bench/summary.ex` — Benchmark result summarization
- `lib/dala_dev/bench/ADBHelper.ex` — ADB command helpers for bench
- `lib/dala_dev/bench/logger.ex` — Bench-specific logging

### Mix Tasks (User-Facing Commands)

**Deployment and connection**:
- `lib/mix/tasks/dala.deploy.ex` — `mix dala.deploy` for deploying builds
- `lib/mix/tasks/dala.push.ex` — `mix dala.push` for hot-pushing code
- `lib/mix/tasks/dala.connect.ex` — `mix dala.connect` for connecting to devices
- `lib/mix/tasks/dala.watch.ex` — `mix dala.watch` for watch-mode development
- `lib/mix/tasks/dala.watch_stop.ex` — Stop a running watch session

**Device management**:
- `lib/mix/tasks/dala.devices.ex` — `mix dala.devices` for listing devices
- `lib/mix/tasks/dala.screen.ex` — `mix dala.screen` for screenshots/video/baselines
- `lib/mix/tasks/dala.reset.ex` — `mix dala.reset` for app force-stop / data wipe
- `lib/mix/tasks/dala.shell.ex` — `mix dala.shell` for app-sandbox shells
- `lib/mix/tasks/dala.port.ex` — `mix dala.port` for the port map and squatters
- `lib/mix/tasks/dala.link.ex` — `mix dala.link` for deep links
- `lib/mix/tasks/dala.clipboard.ex` — `mix dala.clipboard` for device clipboard
- `lib/mix/tasks/dala.location.ex` — `mix dala.location` for location spoofing

**Build and release**:
- `lib/mix/tasks/dala.release.ex` — `mix dala.release` for iOS .ipa builds
- `lib/mix/tasks/dala.release.android.ex` — `mix dala.release.android` for Android .aab builds
- `lib/mix/tasks/dala.publish.ex` — `mix dala.publish` for TestFlight upload
- `lib/mix/tasks/dala.publish.android.ex` — `mix dala.publish.android` for Google Play upload

**Project setup**:
- `lib/mix/tasks/dala.install.ex` — `mix dala.install` for first-run setup
- `lib/mix/tasks/dala.enable.ex` — `mix dala.enable` for feature enablement
- `lib/mix/tasks/dala.icon.ex` — `mix dala.icon` for icon generation
- `lib/mix/tasks/dala.cache.ex` — `mix dala.cache` for cache management
- `lib/mix/tasks/dala.doctor.ex` — `mix dala.doctor` for diagnostics
- `lib/mix/tasks/dala.provision.ex` — `mix dala.provision` for iOS provisioning
- `lib/mix/tasks/dala.routes.ex` — `mix dala.routes` for navigation validation

**Development tools**:
- `lib/mix/tasks/dala_dev.tui.ex` — `mix dala_dev.tui` for interactive TUI dashboard
- `lib/mix/tasks/dala.server.ex` — `mix dala.server` for dev dashboard
- `lib/mix/tasks/dala.web.ex` — `mix dala.web` for comprehensive web UI
- `lib/mix/tasks/dala.gen.live_screen.ex` — `mix dala.gen.live_screen` for LiveView+Screen generation
- `lib/mix/tasks/dala.debug.ex` — `mix dala.debug` for interactive debugging
- `lib/mix/tasks/dala.observer.ex` — `mix dala.observer` for web-based Observer
- `lib/mix/tasks/dala.logs.ex` — `mix dala.logs` for log collection
- `lib/mix/tasks/dala.trace.ex` — `mix dala.trace` for distributed tracing
- `lib/mix/tasks/dala.bench.ex` — `mix dala.bench` for performance benchmarks
- `lib/mix/tasks/dala.env.ex` — `mix dala.env` for the machine-readable env snapshot

**Dala framework tasks** (from the dala repo, available in Dala projects):
- `lib/mix/tasks/dala.verify.ex` — `mix dala.verify` for DSL verification
- `lib/mix/tasks/dala.onboarding_test.ex` — `mix dala.onboarding_test` for onboarding tests
- `lib/mix/tasks/dala.setup_ios_bluetooth.ex` — `mix dala.setup_ios_bluetooth` for iOS BT setup
- `lib/mix/tasks/setup_bluetooth_wifi.ex` — `mix dala.setup_bluetooth_wifi` for BT/WiFi setup
- `lib/mix/tasks/dala/plugin/new.ex` — `mix dala.plugin.new` for plugin scaffolding

**Battery benchmarking**:
- `lib/mix/tasks/dala.battery_bench_android.ex` — Android battery bench
- `lib/mix/tasks/dala.battery_bench_ios.ex` — iOS battery bench

**File transfer**:
- `lib/mix/tasks/dala.push_file.ex` — `mix dala.push_file` for pushing files/folders
- `lib/mix/tasks/dala.pull_file.ex` — `mix dala.pull_file` for pulling files/folders
- `lib/mix/tasks/dala.sync.ex` — `mix dala.sync` for bidirectional directory sync
- `lib/mix/tasks/dala.file_ls.ex` — `mix dala.file_ls` for listing remote files

### Development Server

- `lib/dala_dev/server/` — Phoenix-based dev dashboard
  - `endpoint.ex` — Phoenix endpoint
  - `router.ex` — Route definitions
  - `device_poller.ex` — Periodic device discovery
  - `watch_worker.ex` — File watch and auto-push
  - `log_streamer.ex` — Log streaming from devices
  - `log_buffer.ex` / `elixir_log_buffer.ex` — Log buffering
  - `elixir_logger.ex` — Elixir Logger forwarding
  - `log_filter.ex` — Log filtering

## Maintaining This Document

This file is a living document that should evolve with the codebase. Keep it current to help future contributors (including yourself) avoid past mistakes.

### Related Documentation

- **[Beginner Step-by-Step Guide](guides/beginner_guide.md)** — Getting started with dala_dev from scratch
- **[Development Workflow Guide](guides/development_workflow.md)** — Running, updating, and debugging with dala_dev
- **[Release and Packaging Guide](guides/release_and_packaging.md)** — Building and distributing production apps
- **[Architecture Guide](guides/architecture.md)** — Complete technical reference for dala_dev architecture
- **[Dala Commands Guide](guides/dala_commands.md)** — Complete reference for all `mix dala.*` commands with detailed explanations
- **[Terminal UI (TUI)](guides/tui.md)** — Interactive TUI dashboard with remote debugging, screen info, and version tracking
- **[README.md](README.md)** — Project overview, architecture, and quick command reference
- **[build_release.md](build_release.md)** — Release build walkthrough with step-by-step instructions
- **[Dala AGENTS.md](/Users/manhvu/ohhi/OSS_Lib/dala/AGENTS.md)** — System-wide orientation and pre-empt-failure rules

### When to Update

Update this file in the **same commit** when you:
- Change repository conventions or workflows
- Add a new public API seam (add it to the list above)
- Discover a new gotcha or pitfall (add it to the "Gotchas" section)
- Change the testing strategy or requirements
- Add new Mix tasks or core modules
- Update the release process
- Add or change TUI views, keybindings, or state transitions

### Why It Matters

- **Stale guidance is worse than none** — It leads contributors astray
- **Fresh documentation saves time** — Others won't repeat your mistakes
- **It's part of the code** — Treat documentation updates as seriously as code changes

### Review Checklist

Before merging a PR, verify:
- [ ] All new public functions are documented in the "Public API Seams" section
- [ ] New gotchas are captured in the "Gotchas" section
- [ ] Code examples are correct and copy-pasteable
- [ ] Links to other docs (like `build_release.md`) are still valid
