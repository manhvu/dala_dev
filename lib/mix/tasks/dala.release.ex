defmodule Mix.Tasks.Dala.Release do
  use Mix.Task

  @shortdoc "Build a signed iOS .ipa for App Store / TestFlight"

  @moduledoc """
  Builds a release-signed iOS `.ipa` ready to upload to App Store Connect.

      mix dala.release

  ## Output

  `_build/dala_release/<App>.ipa`

  Use `mix dala.publish` to upload it to TestFlight.

  ## Prerequisites

    1. Apple Developer Program membership (paid, $99/yr)
    2. An "Apple Distribution" certificate in your keychain
       (Xcode → Settings → Accounts → Manage Certificates → +)
    3. An App Store provisioning profile for your bundle ID, downloaded
       to `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`.
       `mix dala.provision --distribution` automates the profile download.

  ## What it does

    1. Resolves a distribution signing identity + App Store profile
       (auto-detect, or `:ios_dist_sign_identity` / `:ios_dist_profile_uuid`
       in `dala.exs`)
    2. Generates `ios/release_device.sh` and runs it:
       - Compiles BEAMs and copies them into the OTP runtime
       - Builds native sources with `-DDALA_RELEASE` so `dala_beam.m`
         drops EPMD + the distribution BEAM args
       - Links the iOS device binary, no EPMD object files
       - Signs the `.app` with the distribution identity (no `get-task-allow`)
       - Packages as `Payload/<App>.app` zipped into `<App>.ipa`

  The shipped `.ipa` runs the full BEAM but with no Erlang distribution
  surface — `Dala.Connectivity.Dist.ensure_started/1` no-ops at runtime when
  `DALA_RELEASE=1`.
  """

  @impl Mix.Task
  def run(_args) do
    DalaDev.Output.configure([])

    case :os.type() do
      {:unix, :darwin} ->
        :ok
        Mix.raise("mix dala.release is only supported on macOS.")
    end

    unless File.dir?("ios") do
      Mix.raise("No ios/ directory found. Run from the root of a dala iOS project.")
    end

    Mix.Task.run("compile")

    case DalaDev.Release.build_ipa() do
      {:ok, path} ->
        DalaDev.Output.info("")
        DalaDev.Output.success("Release build complete")
        DalaDev.Output.info("IPA: #{path}")
        DalaDev.Output.info("Size: #{file_size_human(path)}")
        DalaDev.Output.info("")
        DalaDev.Output.info("Next: mix dala.publish to upload to TestFlight.")

      {:error, reason} ->
        Mix.raise(reason)
    end
  end

  defp file_size_human(path) do
    case File.stat(path) do
      {:ok, %{size: bytes}} ->
        cond do
          bytes >= 1024 * 1024 ->
            :io_lib.format("~.1fM", [bytes / (1024 * 1024)]) |> List.flatten()

          bytes >= 1024 ->
            :io_lib.format("~.1fK", [bytes / 1024]) |> List.flatten()

          true ->
            "#{bytes}B"
        end
        |> to_string()

      _ ->
        "?"
    end
  end

end
