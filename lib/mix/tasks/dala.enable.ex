defmodule Mix.Tasks.Dala.Enable do
  use Mix.Task

  @shortdoc "Enable optional Dala features in this project"

  @moduledoc """
  Enables one or more optional Dala features by patching `mix.exs`, manifest
  files, and generating any required source files.

  ## Usage

      mix dala.enable FEATURE [FEATURE ...]

  Multiple features can be enabled in a single command:

      mix dala.enable camera photo_library
      mix dala.enable camera photo_library file_sharing liveview

  ## Features

  ### `liveview`

  Enables LiveView mode — the Dala app runs a local Phoenix endpoint and displays
  it in a native WebView. Web developers can ship a mobile app with zero native
  UI code.

  What it does:

    - Generates `lib/<app>/dala_screen.ex` — a `Dala.Spark.Dsl` screen that opens a WebView
      at `http://127.0.0.1:PORT/`
    - Injects the `DalaHook` LiveView hook into `assets/js/app.js`
    - Injects a hidden `<div id="dala-bridge" phx-hook="DalaHook">` into
      `root.html.heex` — **this is required for the hook to mount**
    - Updates `dala.exs` with `liveview_port` so `Dala.Platform.LiveView.local_url/1` works

  ### Why the hidden div is required

  Phoenix LiveView hooks only execute when a DOM element carrying
  `phx-hook="DalaHook"` exists in the rendered page. Registering `DalaHook` in
  `app.js` is necessary but not sufficient — without a matching DOM element the
  hook never mounts and `window.dala` is never replaced with the LiveView-backed
  version. Messages would silently route through the native NIF bridge instead
  of the LiveView WebSocket, so `handle_event/3` would never fire.

  See `DalaDev.Enable` module doc and `guides/liveview.md` for the full
  two-bridge architecture explanation.

  After running:

    1. Add `MyApp.DalaScreen` to your supervision tree (or call
       `Dala.Ui.Socket.start_root(MyApp.DalaScreen)` from your `Dala.App.on_start/0`)
    2. Ensure Phoenix is running on the port set in `dala.exs` (default: 4000)

  ### `camera`

  Adds camera permission declarations to platform manifests.

  - iOS: adds `NSCameraUsageDescription` to `ios/*/Info.plist`
  - Android: adds `<uses-permission android:name="android.permission.CAMERA"/>`
    to `android/app/src/main/AndroidManifest.xml`

  ### `photo_library`

  - iOS: adds `NSPhotoLibraryAddUsageDescription` to Info.plist
  - Android: no manifest change needed (API 29+)

  ### `file_sharing`

  - iOS: adds `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`
    to Info.plist
  - Android: adds `<provider android:name="FileProvider">` with paths config

  ### `location`

  - iOS: adds `NSLocationWhenInUseUsageDescription` to Info.plist
  - Android: adds `ACCESS_FINE_LOCATION` permission

  ### `notifications`

  - iOS: runtime only — no plist key needed
  - Android: adds `POST_NOTIFICATIONS` permission (API 33+)
  """

  @valid_features ~w(liveview camera photo_library file_sharing location notifications)

  @impl Mix.Task
  def run([]) do
    DalaDev.Output.configure([])

    DalaDev.Output.error("Usage: mix dala.enable FEATURE [FEATURE ...]")
    DalaDev.Output.info("Valid features: #{Enum.join(@valid_features, ", ")}")
    Mix.raise("No features specified")
  end

  def run(argv) do
    argv = DalaDev.Utils.normalize_cli_args(argv || [])
    DalaDev.Output.configure([])

    {_opts, features, _} = OptionParser.parse(argv, strict: [])

    project_dir = File.cwd!()

    unless File.exists?(Path.join(project_dir, "mix.exs")) do
      Mix.raise("No mix.exs found. Run mix dala.enable from your project root.")
    end

    unknown = features -- @valid_features

    if unknown != [] do
      Mix.raise(
        "Unknown feature(s): #{Enum.join(unknown, ", ")}. " <>
          "Valid: #{Enum.join(@valid_features, ", ")}"
      )
    end

    app_name = read_app_name(project_dir)

    Enum.each(features, fn feature ->
      DalaDev.Output.step("Enabling", feature)
      enable(feature, project_dir, app_name)
    end)

    DalaDev.Output.success("Done.")
  end

  # ── Feature handlers ──────────────────────────────────────────────────────

  defp enable("liveview", project_dir, app_name) do
    generate_dala_screen(project_dir, app_name)
    inject_dala_hook(project_dir)
    inject_dala_bridge_element(project_dir, app_name)
    update_dala_exs(project_dir)
    android_add_liveview_network_config(project_dir)
  end

  defp enable("camera", project_dir, _app_name) do
    ios_add_plist_key(project_dir, "NSCameraUsageDescription", "This app uses the camera.")
    android_add_permission(project_dir, "android.permission.CAMERA")
  end

  defp enable("photo_library", project_dir, _app_name) do
    ios_add_plist_key(
      project_dir,
      "NSPhotoLibraryAddUsageDescription",
      "This app saves photos to your library."
    )

    android_noop("photo_library", "no manifest change needed on API 29+")
  end

  defp enable("file_sharing", project_dir, _app_name) do
    ios_add_plist_key(project_dir, "UIFileSharingEnabled", "true", type: :bool)
    ios_add_plist_key(project_dir, "LSSupportsOpeningDocumentsInPlace", "true", type: :bool)
    android_add_file_provider(project_dir)
  end

  defp enable("location", project_dir, _app_name) do
    ios_add_plist_key(
      project_dir,
      "NSLocationWhenInUseUsageDescription",
      "This app uses your location."
    )

    android_add_permission(project_dir, "android.permission.ACCESS_FINE_LOCATION")
  end

  defp enable("notifications", _project_dir, _app_name) do
    android_noop(
      "notifications",
      "POST_NOTIFICATIONS is requested at runtime, no manifest key needed"
    )

    ios_noop(
      "notifications",
      "iOS notification permission is requested at runtime, no plist key needed"
    )
  end

  # ── LiveView: generate DalaScreen ─────────────────────────────────────────

  defp generate_dala_screen(project_dir, app_name) do
    module_name = Macro.camelize(app_name)
    dir = Path.join([project_dir, "lib", app_name])
    path = Path.join(dir, "dala_screen.ex")

    if File.exists?(path) do
      DalaDev.Output.info("  * skip #{path} (already exists)")
    else
      File.mkdir_p!(dir)
      File.write!(path, dala_screen_template(module_name))
      DalaDev.Output.info(["  * create ", path])
    end
  end

  defp dala_screen_template(module_name) do
    moduledoc = """
      Dala.Spark.Dsl screen that wraps the Phoenix LiveView app in a native WebView.

      Add this to your supervision tree or call from Dala.App.on_start/0:

          Dala.Ui.Socket.start_root(#{module_name}.DalaScreen)
    """

    """
    defmodule #{module_name}.DalaScreen do
      @moduledoc #{inspect(moduledoc)}
      use Dala.Spark.Dsl

      dala do
        screen do
          name :dala
          webview url: Dala.Platform.LiveView.local_url("/"), show_url: false
        end
      end

      def handle_event(event, _params, socket) do
        {:noreply, socket}
      end
    end
    """
  end

  # ── LiveView: inject DalaHook into assets/js/app.js ───────────────────────

  defp inject_dala_hook(project_dir) do
    path = Path.join([project_dir, "assets", "js", "app.js"])

    unless File.exists?(path) do
      DalaDev.Output.warn("  * skip DalaHook injection (#{path} not found)")
      DalaDev.Output.hint("Add the hook manually — see `Dala.Platform.LiveView` docs.")
      return(nil)
    end

    content = File.read!(path)

    if String.contains?(content, "DalaHook") do
      DalaDev.Output.info("  * skip #{path} (DalaHook already present)")
    else
      patched = DalaDev.Enable.inject_dala_hook(content)
      File.write!(path, patched)
      DalaDev.Output.info(["  * patch ", path, " (added DalaHook)"])
    end
  end

  # ── LiveView: inject bridge element into root.html.heex ──────────────────

  defp inject_dala_bridge_element(project_dir, app_name) do
    path = DalaDev.Enable.find_root_html(project_dir, app_name)

    if path do
      content = File.read!(path)

      if String.contains?(content, "dala-bridge") do
        DalaDev.Output.info("  * skip #{path} (dala-bridge already present)")
      else
        patched = DalaDev.Enable.inject_dala_bridge_element(content)
        File.write!(path, patched)
        DalaDev.Output.info(["  * patch ", path, " (added dala-bridge element)"])
      end
    else
      DalaDev.Output.warn("  * skip root.html.heex (not found)")
      DalaDev.Output.hint("Add the following manually inside <body> in your root layout:")
      DalaDev.Output.info("    " <> DalaDev.Enable.dala_bridge_element())
      DalaDev.Output.info("Without this element DalaHook never mounts and window.dala")
      DalaDev.Output.info("will not route through LiveView. See guides/liveview.md.")
    end
  end

  # ── LiveView: update dala.exs ──────────────────────────────────────────────

  defp update_dala_exs(project_dir) do
    path = Path.join(project_dir, "dala.exs")
    liveview_line = "config :dala, liveview_port: 4000"

    if File.exists?(path) do
      content = File.read!(path)

      if String.contains?(content, "liveview_port") do
        DalaDev.Output.info("  * skip #{path} (liveview_port already set)")
      else
        File.write!(path, content <> "\n#{liveview_line}\n")
        DalaDev.Output.info(["  * patch ", path, " (added liveview_port)"])
      end
    else
      File.write!(path, """
      import Config

      #{liveview_line}
      """)

      DalaDev.Output.info(["  * create ", path])
    end
  end

  # ── iOS plist helpers ─────────────────────────────────────────────────────

  defp ios_add_plist_key(project_dir, key, value, opts \\ []) do
    plist = find_ios_plist(project_dir)

    if plist do
      content = File.read!(plist)

      if String.contains?(content, key) do
        DalaDev.Output.info("  * skip #{plist} (#{key} already present)")
      else
        entry = build_plist_entry(key, value, opts)
        patched = String.replace(content, "</dict>\n</plist>", "#{entry}\n</dict>\n</plist>")
        File.write!(plist, patched)
        DalaDev.Output.info(["  * patch ", plist, " (added #{key})"])
      end
    else
      DalaDev.Output.warn("  * skip iOS (no Info.plist found under ios/)")
    end
  end

  defp build_plist_entry(key, value, opts) do
    DalaDev.Enable.build_plist_entry(key, value, opts)
  end

  defp find_ios_plist(project_dir) do
    Path.wildcard(Path.join(project_dir, "ios/**/*.xcodeproj/../*.plist"))
    |> Enum.find(&String.ends_with?(&1, "Info.plist"))
    |> then(fn
      nil ->
        Path.wildcard(Path.join(project_dir, "ios/**/Info.plist"))
        |> List.first()

      path ->
        path
    end)
  end

  defp ios_noop(feature, reason) do
    DalaDev.Output.info("  * iOS #{feature}: #{reason}")
  end

  # ── Android manifest helpers ──────────────────────────────────────────────

  defp android_add_liveview_network_config(project_dir) do
    manifest = find_android_manifest(project_dir)

    if manifest do
      content = File.read!(manifest)

      if String.contains?(content, "networkSecurityConfig") do
        DalaDev.Output.info("  * skip #{manifest} (networkSecurityConfig already present)")
      else
        patched = DalaDev.Enable.inject_android_network_security_config(content)
        File.write!(manifest, patched)

        DalaDev.Output.info([
          "  * patch ",
          manifest,
          " (added networkSecurityConfig for cleartext HTTP to 127.0.0.1)"
        ])
      end

      write_android_network_security_config(project_dir)
    else
      DalaDev.Output.warn("  * skip Android (AndroidManifest.xml not found)")
    end
  end

  defp write_android_network_security_config(project_dir) do
    xml_dir = Path.join([project_dir, "android", "app", "src", "main", "res", "xml"])
    path = Path.join(xml_dir, "network_security_config.xml")

    if File.exists?(path) do
      DalaDev.Output.info("  * skip #{path} (already exists)")
    else
      File.mkdir_p!(xml_dir)
      File.write!(path, DalaDev.Enable.network_security_config_xml())
      DalaDev.Output.info(["  * create ", path])
    end
  end

  defp android_add_permission(project_dir, permission) do
    manifest = find_android_manifest(project_dir)

    if manifest do
      content = File.read!(manifest)
      tag = ~s(<uses-permission android:name="#{permission}"/>)

      if String.contains?(content, permission) do
        DalaDev.Output.info("  * skip #{manifest} (#{permission} already present)")
      else
        patched =
          String.replace(content, "<application", "#{tag}\n    <application", global: false)

        File.write!(manifest, patched)
        DalaDev.Output.info(["  * patch ", manifest, " (added #{permission})"])
      end
    else
      DalaDev.Output.warn("  * skip Android (AndroidManifest.xml not found)")
    end
  end

  defp android_add_file_provider(project_dir) do
    manifest = find_android_manifest(project_dir)

    if manifest do
      content = File.read!(manifest)

      if String.contains?(content, "FileProvider") do
        DalaDev.Output.info("  * skip #{manifest} (FileProvider already present)")
      else
        provider_xml =
          "        <provider\n" <>
            "            android:name=\"androidx.core.content.FileProvider\"\n" <>
            "            android:authorities=\"${applicationId}.fileprovider\"\n" <>
            "            android:exported=\"false\"\n" <>
            "            android:grantUriPermissions=\"true\">\n" <>
            "            <meta-data\n" <>
            "                android:name=\"android.support.FILE_PROVIDER_PATHS\"\n" <>
            "                android:resource=\"@xml/file_provider_paths\"/>\n" <>
            "        </provider>"

        patched =
          String.replace(content, "</application>", "#{provider_xml}\n    </application>",
            global: false
          )

        File.write!(manifest, patched)
        DalaDev.Output.info(["  * patch ", manifest, " (added FileProvider)"])

        write_file_provider_paths(project_dir)
      end
    else
      DalaDev.Output.warn("  * skip Android (AndroidManifest.xml not found)")
    end
  end

  defp write_file_provider_paths(project_dir) do
    xml_dir = Path.join([project_dir, "android", "app", "src", "main", "res", "xml"])
    path = Path.join(xml_dir, "file_provider_paths.xml")

    if File.exists?(path) do
      DalaDev.Output.info("  * skip #{path} (already exists)")
    else
      File.mkdir_p!(xml_dir)

      File.write!(path, """
      <?xml version="1.0" encoding="utf-8"?>
      <paths>
          <files-path name="dala_files" path="." />
          <cache-path name="dala_cache" path="." />
          <external-files-path name="dala_external" path="." />
      </paths>
      """)

      DalaDev.Output.info(["  * create ", path])
    end
  end

  defp find_android_manifest(project_dir) do
    Path.wildcard(Path.join(project_dir, "android/**/AndroidManifest.xml"))
    |> Enum.reject(&String.contains?(&1, "androidTest"))
    |> List.first()
  end

  defp android_noop(feature, reason) do
    DalaDev.Output.info("  * Android #{feature}: #{reason}")
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp read_app_name(project_dir) do
    DalaDev.Enable.read_app_name_from(Path.join(project_dir, "mix.exs"))
  rescue
    e -> Mix.raise(Exception.message(e))
  end

  defp return(val), do: val
end
