defmodule Mix.Tasks.Dala.Release.Android do
  use Mix.Task

  @shortdoc "Build a signed Android App Bundle (.aab) for Google Play"

  @moduledoc """
  Builds a release-signed Android App Bundle (.aab) ready to upload to Google Play.

      mix dala.release.android

  ## Output

  `android/app/build/outputs/bundle/release/app-release.aab`

  Use `mix dala.publish.android` to upload it to Google Play Console.

  ## Prerequisites

    1. Android signing config in `dala.exs`:

           config :dala_dev,
             android_signing: [
               store_file: "~/.android/keystore.jks",
               store_password: "your_store_password",
               key_alias: "your_key_alias",
               key_password: "your_key_password"
             ]

    2. A Google Play Developer account with your app registered

  ## What it does

    1. Downloads OTP runtimes for Android arm64 and arm32
    2. Copies ERTS helper executables into jniLibs
    3. Applies release signing configuration to Gradle
    4. Runs `gradle bundleRelease` to build the AAB
    5. Verifies the AAB was created successfully

  The generated AAB contains both arm64 and arm32 native libraries,
  plus the OTP runtime and compiled BEAM files.
  """

  @impl Mix.Task
  def run(_args) do
    DalaDev.Output.configure([])

    unless File.dir?("android") do
      Mix.raise("No android/ directory found. Run from the root of a dala Android project.")
    end

    Mix.Task.run("compile")

    case DalaDev.NativeBuild.build_all(platforms: [:android], release: true) do
      true ->
        aab_path = Path.expand("android/app/build/outputs/bundle/release/app-release.aab")

        if File.exists?(aab_path) do
          size = File.stat!(aab_path).size
          DalaDev.Output.info("")
          DalaDev.Output.success("Release build complete")
          DalaDev.Output.info("AAB: #{aab_path}")
          DalaDev.Output.info("Size: #{format_size(size)}")
          DalaDev.Output.info("")
          DalaDev.Output.info("Next steps:")
          DalaDev.Output.info("1. Test locally: mix dala.deploy --android")

          DalaDev.Output.info(
            "2. Upload to Google Play: mix dala.publish.android"
          )
        else
          Mix.raise("AAB not found at #{aab_path}. Build may have failed.")
        end

      false ->
        Mix.raise("Android release build failed. See errors above.")
    end
  end

  @spec format_size(non_neg_integer()) :: String.t()
  def format_size(bytes) when bytes >= 1024 * 1024 do
    :io_lib.format("~.1fM", [bytes / (1024 * 1024)]) |> List.flatten() |> to_string()
  end

  def format_size(bytes) when bytes >= 1024 do
    :io_lib.format("~.1fK", [bytes / 1024]) |> List.flatten() |> to_string()
  end

  def format_size(bytes), do: "#{bytes}B"

end
