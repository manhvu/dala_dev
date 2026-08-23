defmodule DalaDev.Config do
  @moduledoc false

  # Shared config helpers used across deployer, connector, native_build, and
  # battery bench tasks.

  # Note: Regex compilation is now centralized in DalaDev.Utils.compile_regex/2
  # New code should prefer that over calling Regex.compile! directly.

  @doc """
  Returns the app's bundle ID / Android package name.

  Resolution order:
    1. `dala.exs` — `config :dala_dev, bundle_id: "..."` (opt-in override;
       not required — projects work fine without it)
    2. `ios/Info.plist` — `CFBundleIdentifier`
    3. `android/app/build.gradle` — `applicationId`
    4. Generated default: `"<DALA_BUNDLE_PREFIX or com.example>.<app_name>"`

  The four-level fallback exists so cross-platform tasks (e.g. `mix dala.deploy`)
  always have a value to work with, regardless of which platform's manifest is
  authoritative for the project. For most users, the value resolved at step 2
  or 3 is what `mix dala.new` wrote there at generation time; dala.exs is
  reserved for explicit overrides.
  """
  @spec bundle_id() :: String.t()
  def bundle_id do
    load_dala_config()[:bundle_id] ||
      detect_from_ios_plist() ||
      detect_from_android_gradle() ||
      "#{bundle_prefix()}.#{app_name()}"
  end

  # Default reverse-DNS prefix when no platform manifest is available. Honors
  # DALA_BUNDLE_PREFIX so users with a corporate prefix can set it once.
  # Mirrors DalaNew.ProjectGenerator.bundle_prefix/0 so the generator's default
  # and the runtime fallback agree.
  defp bundle_prefix do
    case System.get_env("DALA_BUNDLE_PREFIX") do
      nil -> "com.example"
      "" -> "com.example"
      raw -> String.trim(raw)
    end
  end

  @doc """
  Reads the `dala_dev` section from `dala.exs` in the current directory.
  Returns an empty keyword list if the file does not exist.
  """
  @spec load_dala_config() :: keyword()
  def load_dala_config, do: load_dala_config_from(File.cwd!())

  @doc false
  # Test seam: same as `load_dala_config/0` but reads from an explicit project
  # directory, so tests don't have to mutate the VM-global CWD.
  @spec load_dala_config_from(Path.t()) :: keyword()
  def load_dala_config_from(project_dir) do
    config_file = Path.join(project_dir, "dala.exs")

    if File.exists?(config_file),
      do: Config.Reader.read!(config_file) |> Keyword.get(:dala_dev, []),
      else: []
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp detect_from_ios_plist do
    plist = Path.join([File.cwd!(), "ios", "Info.plist"])

    with true <- File.exists?(plist),
         {:ok, content} <- File.read(plist),
         [_, id] <-
           Regex.run(
             DalaDev.Utils.compile_regex(
               "<key>CFBundleIdentifier</key>\\s*<string>([^<]+)</string>"
             ),
             content
           ) do
      id
    else
      _ -> nil
    end
  end

  defp detect_from_android_gradle do
    gradle = Path.join([File.cwd!(), "android", "app", "build.gradle"])

    with true <- File.exists?(gradle),
         {:ok, content} <- File.read(gradle),
         match when match != nil <-
           Regex.run(
             DalaDev.Utils.compile_regex("applicationId\\s+[\"']([^\"']+)[\"']"),
             content
           ) ||
             Regex.run(
               DalaDev.Utils.compile_regex("applicationId\\s*=\\s*[\"']([^\"']+)[\"']"),
               content
             ) do
      Enum.at(match, 1)
    else
      _ -> nil
    end
  end

  defp app_name, do: Mix.Project.config()[:app] |> to_string()
end
