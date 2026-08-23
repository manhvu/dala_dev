defmodule Mix.Tasks.Dala.Provision do
  use Mix.Task

  @shortdoc "Register your app ID and download an iOS provisioning profile"

  @moduledoc """
  Registers your app's bundle ID with Apple and downloads an iOS
  provisioning profile.

  Two modes:

      mix dala.provision                 # development profile (default)
      mix dala.provision --distribution  # App Store distribution profile

  Run development provisioning once before your first `mix dala.deploy --native`.
  Run distribution provisioning once before your first `mix dala.release`.

  ## What you need first

    1. **Apple ID** — free at https://appleid.apple.com
    2. **Xcode signed in** with that Apple ID:
       open Xcode → Settings → Accounts → [+] → Apple ID
    3. **Apple Developer Program** — optional for personal device development,
       required for App Store distribution ($99/year).
       Free accounts can deploy to their own devices; profiles expire every
       7 days. Paid accounts get 1-year profiles and App Store access.
       Enroll at https://developer.apple.com/programs/enroll/

  Distribution mode requires a paid Developer Program membership.

  ## What it does (development)

    1. Reads your signing team from the macOS keychain or existing profiles
    2. Generates `ios/Provision.xcodeproj` — a minimal Xcode project used
       only for provisioning (safe to commit)
    3. Generates `ios/DalaProvision.swift` — a two-line SwiftUI stub
    4. Runs `xcodebuild -allowProvisioningUpdates build` which contacts
       Apple to:
       - Register your bundle ID in your developer account (if not registered)
       - Create a development provisioning profile
       - Download it to ~/Library/Developer/Xcode/.../Provisioning Profiles/
    5. Verifies the profile is present

  ## What it does (distribution)

  Same as above, but runs `xcodebuild archive -allowProvisioningUpdates`
  with `CODE_SIGN_STYLE=Automatic` against the Release configuration.
  Apple creates an App Store provisioning profile (and an Apple
  Distribution certificate, if missing) and downloads them to your
  keychain + provisioning profile directory.
  """

  @switches [distribution: :boolean]

  @impl Mix.Task
  def run(argv) do
    argv = DalaDev.Utils.normalize_cli_args(argv || [])

    DalaDev.Output.configure([])

    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    mode = if opts[:distribution], do: :distribution, else: :development

    unless macos?() do
      Mix.raise("mix dala.provision is only supported on macOS.")
    end

    unless File.dir?("ios") do
      Mix.raise("No ios/ directory found. Run from the root of a dala iOS project.")
    end

    DalaDev.Output.info("")
    label = if mode == :distribution, do: "Distribution", else: "Development"
    DalaDev.Output.step("iOS Provisioning (#{label})")
    DalaDev.Output.info("")
    DalaDev.Output.info("What you need before this step:")
    DalaDev.Output.info("")
    DalaDev.Output.info("1. Apple ID — free at https://appleid.apple.com")
    DalaDev.Output.info("2. Xcode signed in with that Apple ID")
    DalaDev.Output.info("Open Xcode → Settings → Accounts → [+] → Apple ID")
    DalaDev.Output.info("3. (App Store only) Apple Developer Program — $99/year")
    DalaDev.Output.info("Free accounts work for deploying to your own devices.")
    DalaDev.Output.info("")
    DalaDev.Output.step("Checking")
    DalaDev.Output.info("")

    check_signing_identity!(mode)
    team_id = resolve_team_id()
    bundle_id = check_bundle_id!()

    DalaDev.Output.info("")
    DalaDev.Output.info("Bundle ID : #{bundle_id}")
    DalaDev.Output.info("Team ID   : #{team_id}")
    DalaDev.Output.info("")

    # For distribution mode: if the user already has an App Store profile
    # for this bundle ID locally, use its actual UUID rather than guessing
    # the name. xcodebuild's PROVISIONING_PROFILE_SPECIFIER accepts both
    # names and UUIDs; UUIDs are unambiguous and survive any naming
    # convention the user picked when they downloaded the profile from
    # developer.apple.com or via Xcode UI.
    #
    # For dev mode the Release config isn't used (build action defaults
    # to Debug), but the pbxproj template always emits both configs, so
    # we pass the predicted name as a harmless placeholder.
    profile_specifier =
      case mode do
        :distribution ->
          discover_dist_profile(bundle_id, team_id) || default_profile_name(bundle_id)

        _ ->
          default_profile_name(bundle_id)
      end

    generate_xcodeproj(bundle_id, team_id, profile_specifier)
    generate_swift_stub()

    DalaDev.Output.info("")
    DalaDev.Output.step("Contacting Apple to register App ID and download profile")
    DalaDev.Output.info("(requires internet — may take 10–30 seconds)")
    DalaDev.Output.info("")

    run_xcodebuild!(mode)
    verify_profile!(bundle_id, mode)

    DalaDev.Output.info("")
    DalaDev.Output.success("Provisioning complete!")
    DalaDev.Output.info("")

    case mode do
      :distribution ->
        DalaDev.Output.info("Next step: mix dala.release")

      _ ->
        DalaDev.Output.info("Next step: mix dala.deploy --native")
    end

    DalaDev.Output.info("")

    DalaDev.Output.hint(
      "Free Apple ID profiles expire every 7 days — re-run mix dala.provision when that happens."
    )

    DalaDev.Output.hint("Paid Developer Program profiles last 1 year.")
  end

  # ── Prerequisite checks ───────────────────────────────────────────────────────

  defp check_signing_identity!(mode) do
    cert_kind =
      case mode do
        :distribution -> "Apple Distribution"
        _ -> "Apple Development"
      end

    case System.cmd("security", ["find-identity", "-v", "-p", "codesigning"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        identities =
          Regex.scan(Regex.compile!("\\d+\\) [0-9A-F]+ \"([^\"]+)\""), output)
          |> Enum.map(fn [_, id] -> id end)
          |> Enum.filter(&String.contains?(&1, cert_kind))
          |> Enum.uniq()

        case identities do
          [] ->
            # For distribution, xcodebuild -allowProvisioningUpdates with the
            # archive action can create the cert if missing — so this isn't
            # fatal in distribution mode. Just warn and let xcodebuild try.
            DalaDev.Output.warn("#{cert_kind} certificate — not yet in keychain")

            if mode == :distribution do
              DalaDev.Output.info(
                "xcodebuild will attempt to create one when contacting Apple."
              )
            else
              Mix.raise("""

              No #{cert_kind} signing certificate found.

              One-time setup:
                1. Open Xcode
                2. Xcode → Settings → Accounts → [+] → add your Apple ID
                3. Select your team → click "Manage Certificates" → "+"
                4. Re-run: mix dala.provision
              """)
            end

          [id] ->
            DalaDev.Output.success("Signing certificate — #{id}")

          many ->
            DalaDev.Output.success(
              "Signing certificate — #{hd(many)} (#{length(many)} found, using first)"
            )
        end

      _ ->
        Mix.raise("Could not query keychain — is this macOS?")
    end
  end

  defp resolve_team_id do
    cfg = DalaDev.Config.load_dala_config()

    cond do
      team = cfg[:ios_team_id] ->
        DalaDev.Output.success("Team ID — #{team} (from dala.exs)")
        team

      team = team_from_any_profile() ->
        DalaDev.Output.success("Team ID — #{team} (auto-detected from existing profile)")

        team

      true ->
        DalaDev.Output.warn("Team ID — could not auto-detect")

        DalaDev.Output.info("Paid Apple Developer Program ($99/yr):")

        DalaDev.Output.info("https://developer.apple.com/account → Membership → Team ID")

        DalaDev.Output.info("Free tier (Personal Team, no $99):")
        DalaDev.Output.info("Xcode → Settings → Accounts → [your Apple ID] → Team column")

        team = Mix.shell().prompt("  Enter Team ID:") |> String.trim()

        unless Regex.match?(Regex.compile!("^[A-Z0-9]{10}$"), team) do
          Mix.raise(
            "Invalid Team ID '#{team}' — expected 10 uppercase alphanumeric characters (e.g. Q89CW299G8)"
          )
        end

        team
    end
  end

  defp team_from_any_profile do
    profile_dirs = [
      Path.expand("~/Library/Developer/Xcode/UserData/Provisioning Profiles"),
      Path.expand("~/Library/MobileDevice/Provisioning Profiles")
    ]

    Enum.flat_map(profile_dirs, &Path.wildcard(Path.join(&1, "*.mobileprovision")))
    |> Enum.find_value(fn path ->
      with {:ok, data} <- File.read(path),
           {s, _} <- :binary.match(data, "<?xml"),
           {e, len} <- :binary.match(data, "</plist>") do
        xml = binary_part(data, s, e - s + len)

        case Regex.run(
               Regex.compile!("<key>TeamIdentifier</key>\\s*<array>\\s*<string>([^<]+)</string>"),
               xml
             ) do
          [_, team] -> String.trim(team)
          _ -> nil
        end
      else
        _ -> nil
      end
    end)
  end

  defp check_bundle_id! do
    bundle_id = DalaDev.Config.bundle_id()
    DalaDev.Output.success("Bundle ID — #{bundle_id}")
    bundle_id
  end

  # ── File generation ───────────────────────────────────────────────────────────

  defp generate_xcodeproj(bundle_id, team_id, profile_specifier) do
    proj_dir = "ios/Provision.xcodeproj"
    proj_file = Path.join(proj_dir, "project.pbxproj")
    expected = project_pbxproj(bundle_id, team_id, profile_specifier)

    needs_write =
      case File.read(proj_file) do
        {:ok, ^expected} -> false
        # Any drift — wrong bundle/team, different profile specifier
        # (user downloaded a new profile), missing settings added in
        # newer dala_dev versions, hand-edits — gets rewritten. Cheap to
        # do (one local file write) and catches the common "old project
        # generated by an older dala_dev" trap on upgrade.
        _ -> true
      end

    if needs_write do
      DalaDev.Output.info("Writing ios/Provision.xcodeproj...")
      File.mkdir_p!(proj_dir)
      File.write!(proj_file, expected)
    else
      DalaDev.Output.success("ios/Provision.xcodeproj — up to date")
    end
  end

  # Discover an existing App Store profile for the bundle ID by parsing
  # the profiles in ~/Library/Developer/Xcode/UserData/Provisioning Profiles/.
  # Returns the profile UUID (preferred over name — UUIDs don't change
  # if the user renames their profile), or nil if none found.
  #
  # Reuses DalaDev.Release.parse_mobileprovision/1 which already filters
  # for App Store profiles (no provisioned-devices, no provisions-all-devices).
  defp discover_dist_profile(bundle_id, team_id) do
    profile_dirs = [
      Path.expand("~/Library/Developer/Xcode/UserData/Provisioning Profiles"),
      Path.expand("~/Library/MobileDevice/Provisioning Profiles")
    ]

    matches =
      profile_dirs
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "*.mobileprovision")))
      |> Enum.flat_map(&DalaDev.Release.parse_mobileprovision/1)
      |> Enum.filter(fn p ->
        # App Store profile (not dev / ad-hoc / enterprise) for our bundle + team.
        not p.provisioned_devices? and not p.provisions_all_devices? and
          p.team_id == team_id and
          (String.ends_with?(p.app_id, ".#{bundle_id}") or
             String.ends_with?(p.app_id, ".*"))
      end)

    case matches do
      [%{uuid: uuid}] ->
        DalaDev.Output.success("App Store profile — found locally (UUID #{uuid})")
        uuid

      [] ->
        nil

      many ->
        # Prefer exact bundle ID over wildcard.
        exact = Enum.filter(many, &String.ends_with?(&1.app_id, ".#{bundle_id}"))

        case exact do
          [%{uuid: uuid} | _] ->
            DalaDev.Output.success("App Store profile — found locally (UUID #{uuid})")
            uuid

          [] ->
            %{uuid: uuid} = hd(many)

            DalaDev.Output.warn(
              "Multiple wildcard profiles match — using first (UUID #{uuid})"
            )

            uuid
        end
    end
  end

  # Fallback profile-specifier name pattern (used only when no profile is
  # locally cached yet — first --distribution run before the user has
  # downloaded anything). Won't match a user-renamed profile, but xcodebuild
  # will produce a clear "no profile matching..." error in that case which
  # our diagnose_xcodebuild_failure picks up.
  defp default_profile_name(bundle_id),
    do: "iOS Team Store Provisioning Profile: #{bundle_id}"

  defp generate_swift_stub do
    path = "ios/DalaProvision.swift"

    if File.exists?(path) do
      DalaDev.Output.success("ios/DalaProvision.swift — already exists")
    else
      DalaDev.Output.info("Writing ios/DalaProvision.swift...")

      File.write!(path, """
      import SwiftUI

      @main
      struct DalaProvision: App {
          var body: some Scene { WindowGroup { EmptyView() } }
      }
      """)
    end
  end

  # ── xcodebuild ────────────────────────────────────────────────────────────────

  defp run_xcodebuild!(mode) do
    # `-scheme DalaProvision` rather than `-target DalaProvision`: Xcode 16+
    # rejects `-archivePath` paired with `-target` ("The flag -scheme is
    # required when specifying -archivePath but not -exportArchive").
    # Both forms work for the build action, so we use scheme for both
    # to keep the invocation consistent.
    base = [
      "-project",
      "ios/Provision.xcodeproj",
      "-scheme",
      "DalaProvision",
      "-destination",
      "generic/platform=iOS",
      "-allowProvisioningUpdates",
      "-allowProvisioningDeviceRegistration"
    ]

    args =
      case mode do
        :distribution ->
          # `archive` + Release config triggers Apple to create or refresh
          # the App Store provisioning profile (and Distribution cert if
          # missing) under automatic signing.
          #
          # Don't override SYMROOT/OBJROOT for archive — Xcode 26's
          # archive action expects its own DerivedData layout (creates
          # ArchiveIntermediates/.../BuildProductsPath/SwiftSupport
          # internally), and pointing OBJROOT to /tmp leaves
          # BuildProductsPath unwritten and the archive packaging step
          # fails with "BuildProductsPath couldn't be opened".
          base ++
            [
              "-configuration",
              "Release",
              "-archivePath",
              "/tmp/dala_provision_build/Provision.xcarchive",
              "archive"
            ]

        _ ->
          # Build action is fine with the /tmp scratch dir — only the
          # archive action has the BuildProductsPath layout requirement.
          base ++
            [
              "SYMROOT=/tmp/dala_provision_build",
              "OBJROOT=/tmp/dala_provision_build",
              "build"
            ]
      end

    {output, rc} = System.cmd("xcodebuild", args, stderr_to_stdout: true)

    if rc != 0 do
      # Show the full xcodebuild output first — keeps Apple's exact error
      # text visible for google searches and for users comparing notes with
      # online answers. The targeted hint below it is additive.
      DalaDev.Output.info(output)

      hint = diagnose_xcodebuild_failure(output)
      Mix.raise(format_xcodebuild_error(rc, hint, args))
    end

    # Print only the summary line on success
    output
    |> String.split("\n")
    |> Enum.filter(&(&1 =~ Regex.compile!("^\\*\\* BUILD (SUCCEEDED|FAILED)")))
    |> Enum.each(&DalaDev.Output.info/1)

    :ok
  end

  # ── xcodebuild error diagnosis ────────────────────────────────────────────
  #
  # Pattern-match against known Apple error strings and return a {label,
  # snippet, hint} describing the targeted fix. Returns nil for unmatched
  # errors — the caller falls back to a generic "common causes" message.
  #
  # The Apple/xcodebuild text is preserved verbatim in `:snippet` so users
  # can paste it into a search engine and find existing community
  # answers — our hint is additive, not a replacement.
  #
  # ## URL stability
  #
  # Each hint includes a link to Apple's official docs (`developer.apple.com/help/account/...`),
  # which is Apple's account-management knowledge base — more stable than
  # blog posts or Developer Forum threads. Apple does occasionally
  # reorganise these; if a link 404s, search "site:developer.apple.com"
  # for the section title to find its new home, then update the
  # `@apple_url_*` module attributes below. The pattern matchers are the
  # long-term backstop: they catch the error even when the URL goes stale.

  @apple_url_app_id "https://developer.apple.com/help/account/identifiers/register-an-app-id"
  @apple_url_signing_cert "https://developer.apple.com/help/account/create-certificates/create-signing-certificates"
  @apple_url_team_id "https://developer.apple.com/help/account/manage-your-team/locate-your-team-id"

  @doc false
  @spec diagnose_xcodebuild_failure(String.t()) ::
          {label :: String.t(), snippet :: String.t(), hint :: String.t()} | nil
  def diagnose_xcodebuild_failure(output) do
    cond do
      snippet = match_no_store_profile(output) ->
        {"Distribution profile can't be auto-created for an unregistered App ID", snippet,
         """
         xcodebuild can manage existing profiles via -allowProvisioningUpdates,
         but it won't register a brand-new bundle ID *and* create the App
         Store profile in one shot — Apple's distribution flow needs the
         App ID to exist first.

         Register the App ID once (1 minute), then re-run mix dala.provision:

           1. https://developer.apple.com/account/resources/identifiers/list
           2. Click + → App IDs → Continue → App → Continue
           3. Description: <your app name>
              Bundle ID: select Explicit, paste your bundle id
              Capabilities: leave defaults
           4. Continue → Register

         Then: mix dala.provision --distribution
         """}

      snippet = match_invalid_app_id_name(output) ->
        {"Apple rejected the auto-generated App ID display name", snippet,
         """
         Apple derives the App ID display name from your bundle ID by
         prepending "XC " and replacing dots with spaces. The result has
         to fit Apple's portal validation (~30-char limit, no characters
         their validator rejects — underscores have been flagged in some
         years).

         Fix: shorten the bundle ID's last segment in dala.exs:

             config :dala_dev, bundle_id: "com.example.<short_name>"

         Or regenerate with a shorter app name:

             mix dala.new <short_name>

         Apple's App ID rules: #{@apple_url_app_id}
         """}

      snippet = match_no_signing_cert(output) ->
        {"No Apple Development signing certificate", snippet,
         """
         Open Xcode → Settings → Accounts:
           1. [+] → add your Apple ID (free at https://appleid.apple.com)
           2. select your team → "Manage Certificates" → "+" → Apple Development

         Then re-run `mix dala.provision`.

         Apple's signing certificate guide: #{@apple_url_signing_cert}
         """}

      snippet = match_no_team(output) ->
        {"No team available for signing", snippet,
         """
         Set your Team ID in dala.exs:

             config :dala_dev, ios_team_id: "ABC123XYZ4"

         Find yours at:
           Paid ($99/yr): https://developer.apple.com/account → Membership
           Free (Personal Team): Xcode → Settings → Accounts →
                                 [your Apple ID] → Team column

         Apple's "locate your Team ID" guide: #{@apple_url_team_id}
         """}

      snippet = match_app_id_quota(output) ->
        {"Free-tier App ID limit (3 per 7 days) hit", snippet,
         """
         Apple caps Personal Team accounts at 3 distinct bundle IDs
         registered per rolling 7-day window. Either wait it out, or
         reuse a bundle ID Xcode already provisioned for you by setting
         it explicitly in dala.exs:

             config :dala_dev, bundle_id: "com.example.<previously_registered>"

         Apple's App ID registration page (mentions registration limits):
         #{@apple_url_app_id}
         """}

      snippet = match_bundle_id_taken(output) ->
        {"Bundle ID belongs to a different team", snippet,
         """
         Apple won't let two teams own the same App ID. Pick a unique
         bundle ID — for personal projects, append your initials or a
         random suffix:

             config :dala_dev, bundle_id: "com.example.<app>.<your_suffix>"

         Or change MOB_BUNDLE_PREFIX away from the conflicting reverse-DNS.

         Apple's App ID rules (uniqueness across teams):
         #{@apple_url_app_id}
         """}

      true ->
        nil
    end
  end

  # Each match_* helper returns the verbatim snippet from xcodebuild output
  # if the pattern is present, else nil. Keeping the snippet in the user's
  # output (rather than rephrasing) keeps it google-searchable.

  defp match_no_store_profile(output) do
    grep_first(output, "iOS Team Store Provisioning Profile") &&
      grep_first(output, "No profile for team")
  end

  defp match_invalid_app_id_name(output) do
    grep_first(output, "The attribute 'name' is invalid")
  end

  defp match_no_signing_cert(output) do
    grep_first(output, "No signing certificate") ||
      grep_first(output, "no Apple Development cert") ||
      grep_first(output, "requires a development team")
  end

  defp match_no_team(output) do
    grep_first(output, "no eligible accounts") ||
      grep_first(output, "doesn't include any iOS App Development") ||
      grep_first(output, "No development team")
  end

  defp match_app_id_quota(output) do
    grep_first(output, "There are too many App IDs") ||
      grep_first(output, "maximum allowed number of App IDs") ||
      grep_first(output, "Maximum App IDs Reached")
  end

  defp match_bundle_id_taken(output) do
    grep_first(output, "Failed to register bundle identifier") ||
      grep_first(output, "An App ID with Identifier") ||
      grep_first(output, "is not available. Please enter a different string")
  end

  # First line of `output` containing `needle`, or nil.
  defp grep_first(output, needle) do
    output
    |> String.split("\n")
    |> Enum.find(&String.contains?(&1, needle))
    |> case do
      nil -> nil
      line -> String.trim(line)
    end
  end

  defp format_xcodebuild_error(rc, nil, args) do
    """

    xcodebuild provisioning failed (exit #{rc}).

    Common causes:
      - Xcode not signed in: open Xcode → Settings → Accounts → add Apple ID
      - Bundle ID registered to a different team
      - No internet connection (provisioning contacts Apple's servers)
      - Free-tier Apple ID hit the 3-App-IDs-per-7-days limit

    The full xcodebuild output is above; search any error line you don't
    recognise — Apple's text is fairly distinctive and there's almost always
    a Stack Overflow / forum hit for it.

    To debug, run manually from #{File.cwd!()}:
        xcodebuild #{Enum.join(args, " ")}
    """
  end

  defp format_xcodebuild_error(rc, {label, snippet, hint}, _args) do
    """

    xcodebuild provisioning failed (exit #{rc}).

    #{IO.ANSI.bright()}#{label}#{IO.ANSI.reset()}

    Apple's exact error (paste this into a search engine for community answers):

        #{snippet}

    #{hint}
    """
  end

  defp verify_profile!(bundle_id, mode) do
    profile_dirs = [
      Path.expand("~/Library/Developer/Xcode/UserData/Provisioning Profiles"),
      Path.expand("~/Library/MobileDevice/Provisioning Profiles")
    ]

    matching =
      Enum.flat_map(profile_dirs, &Path.wildcard(Path.join(&1, "*.mobileprovision")))
      |> Enum.filter(fn path ->
        case File.read(path) do
          {:ok, data} ->
            bundle_match =
              String.contains?(data, bundle_id) or
                Regex.match?(
                  Regex.compile!(
                    "<key>application-identifier</key>\\s*<string>[^<]+\\.\\*</string>"
                  ),
                  data
                )

            mode_match =
              case mode do
                :distribution ->
                  # App Store profiles have no ProvisionedDevices array
                  not String.contains?(data, "<key>ProvisionedDevices</key>") and
                    not String.contains?(data, "<key>ProvisionsAllDevices</key>")

                _ ->
                  # Development profiles list ProvisionedDevices
                  String.contains?(data, "<key>ProvisionedDevices</key>")
              end

            bundle_match and mode_match

          _ ->
            false
        end
      end)

    if matching != [] do
      label = if mode == :distribution, do: "App Store", else: "development"
      DalaDev.Output.success("#{label} provisioning profile ready")
    else
      DalaDev.Output.warn(
        "Profile not found — re-run `mix dala.provision#{if mode == :distribution, do: " --distribution", else: ""}` if needed"
      )
    end
  end

  # ── project.pbxproj template ──────────────────────────────────────────────────
  #
  # Release config note: Manual signing + explicit Apple Distribution
  # identity is the Apple-blessed pattern when the team already has a
  # wildcard Apple Development profile (most do). Under automatic
  # signing, Xcode greedily picks that wildcard profile (it satisfies
  # the bundle ID), never enters distribution mode, and then refuses
  # any manual identity override with "conflicting provisioning
  # settings". Manual + `-allowProvisioningUpdates` tells xcodebuild
  # "fetch (and create at Apple if needed) the App Store profile for
  # this bundle ID" — which is exactly what we want for the one-shot
  # provision flow.
  #
  # A minimal Xcode project with a single Swift target. The UUIDs are fixed (they
  # only need to be unique within this file). DalaProvision.swift is referenced
  # relative to the ios/ directory (the directory containing Provision.xcodeproj).

  defp project_pbxproj(bundle_id, team_id, profile_specifier)
       when is_binary(profile_specifier) do
    """
    // !$*UTF8*$!
    {
    \tarchiveVersion = 1;
    \tclasses = {
    \t};
    \tobjectVersion = 77;
    \tobjects = {

    /* Begin PBXBuildFile section */
    \t\tAA000001 /* DalaProvision.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA000002 /* DalaProvision.swift */; };
    /* End PBXBuildFile section */

    /* Begin PBXFileReference section */
    \t\tAA000002 /* DalaProvision.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DalaProvision.swift; sourceTree = "<group>"; };
    \t\tAA000003 /* DalaProvision.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = DalaProvision.app; sourceTree = BUILT_PRODUCTS_DIR; };
    /* End PBXFileReference section */

    /* Begin PBXGroup section */
    \t\tAA000004 = {
    \t\t\tisa = PBXGroup;
    \t\t\tchildren = (
    \t\t\t\tAA000002 /* DalaProvision.swift */,
    \t\t\t\tAA000005 /* Products */,
    \t\t\t);
    \t\t\tsourceTree = "<group>";
    \t\t};
    \t\tAA000005 /* Products */ = {
    \t\t\tisa = PBXGroup;
    \t\t\tchildren = (
    \t\t\t\tAA000003 /* DalaProvision.app */,
    \t\t\t);
    \t\t\tname = Products;
    \t\t\tsourceTree = "<group>";
    \t\t};
    /* End PBXGroup section */

    /* Begin PBXNativeTarget section */
    \t\tAA000006 /* DalaProvision */ = {
    \t\t\tisa = PBXNativeTarget;
    \t\t\tbuildConfigurationList = AA000007 /* Build configuration list for PBXNativeTarget "DalaProvision" */;
    \t\t\tbuildPhases = (
    \t\t\t\tAA000008 /* Sources */,
    \t\t\t);
    \t\t\tbuildRules = (
    \t\t\t);
    \t\t\tdependencies = (
    \t\t\t);
    \t\t\tname = DalaProvision;
    \t\t\tproductName = DalaProvision;
    \t\t\tproductReference = AA000003 /* DalaProvision.app */;
    \t\t\tproductType = "com.apple.product-type.application";
    \t\t};
    /* End PBXNativeTarget section */

    /* Begin PBXProject section */
    \t\tAA000009 /* Project object */ = {
    \t\t\tisa = PBXProject;
    \t\t\tattributes = {
    \t\t\t\tBuildIndependentTargetsInParallel = YES;
    \t\t\t\tLastUpgradeCheck = 1600;
    \t\t\t};
    \t\t\tbuildConfigurationList = AA00000A /* Build configuration list for PBXProject "Provision" */;
    \t\t\tdevelopmentRegion = en;
    \t\t\thasScannedForEncodings = 0;
    \t\t\tknownRegions = (
    \t\t\t\tBase,
    \t\t\t\ten,
    \t\t\t);
    \t\t\tmainGroup = AA000004;
    \t\t\tproductRefGroup = AA000005 /* Products */;
    \t\t\tprojectDirPath = "";
    \t\t\tprojectRoot = "";
    \t\t\ttargets = (
    \t\t\t\tAA000006 /* DalaProvision */,
    \t\t\t);
    \t\t};
    /* End PBXProject section */

    /* Begin PBXSourcesBuildPhase section */
    \t\tAA000008 /* Sources */ = {
    \t\t\tisa = PBXSourcesBuildPhase;
    \t\t\tbuildActionMask = 2147483647;
    \t\t\tfiles = (
    \t\t\t\tAA000001 /* DalaProvision.swift in Sources */,
    \t\t\t);
    \t\t\trunOnlyForDeploymentPostprocessing = 0;
    \t\t};
    /* End PBXSourcesBuildPhase section */

    /* Begin XCBuildConfiguration section */
    \t\tAA00000B /* Debug */ = {
    \t\t\tisa = XCBuildConfiguration;
    \t\t\tbuildSettings = {
    \t\t\t\tCODE_SIGN_STYLE = Automatic;
    \t\t\t\tDEVELOPMENT_TEAM = #{team_id};
    \t\t\t\tGENERATE_INFOPLIST_FILE = YES;
    \t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
    \t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
    \t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
    \t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = #{bundle_id};
    \t\t\t\tPRODUCT_NAME = DalaProvision;
    \t\t\t\tSDKROOT = iphoneos;
    \t\t\t\tSWIFT_VERSION = 5.9;
    \t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
    \t\t\t};
    \t\t\tname = Debug;
    \t\t};
    \t\tAA00000C /* Release */ = {
    \t\t\tisa = XCBuildConfiguration;
    \t\t\tbuildSettings = {
    \t\t\t\tCODE_SIGN_STYLE = Manual;
    \t\t\t\tCODE_SIGN_IDENTITY = "Apple Distribution";
    \t\t\t\t"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Distribution";
    \t\t\t\tDEVELOPMENT_TEAM = #{team_id};
    \t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "#{profile_specifier}";
    \t\t\t\tGENERATE_INFOPLIST_FILE = YES;
    \t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
    \t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
    \t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
    \t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = #{bundle_id};
    \t\t\t\tPRODUCT_NAME = DalaProvision;
    \t\t\t\tSDKROOT = iphoneos;
    \t\t\t\tSWIFT_VERSION = 5.9;
    \t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
    \t\t\t};
    \t\t\tname = Release;
    \t\t};
    \t\tAA00000D /* Debug */ = {
    \t\t\tisa = XCBuildConfiguration;
    \t\t\tbuildSettings = {
    \t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
    \t\t\t\tSDKROOT = iphoneos;
    \t\t\t};
    \t\t\tname = Debug;
    \t\t};
    \t\tAA00000E /* Release */ = {
    \t\t\tisa = XCBuildConfiguration;
    \t\t\tbuildSettings = {
    \t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
    \t\t\t\tSDKROOT = iphoneos;
    \t\t\t};
    \t\t\tname = Release;
    \t\t};
    /* End XCBuildConfiguration section */

    /* Begin XCConfigurationList section */
    \t\tAA000007 /* Build configuration list for PBXNativeTarget "DalaProvision" */ = {
    \t\t\tisa = XCConfigurationList;
    \t\t\tbuildConfigurations = (
    \t\t\t\tAA00000B /* Debug */,
    \t\t\t\tAA00000C /* Release */,
    \t\t\t);
    \t\t\tdefaultConfigurationIsVisible = 0;
    \t\t\tdefaultConfigurationName = Debug;
    \t\t};
    \t\tAA00000A /* Build configuration list for PBXProject "Provision" */ = {
    \t\t\tisa = XCConfigurationList;
    \t\t\tbuildConfigurations = (
    \t\t\t\tAA00000D /* Debug */,
    \t\t\t\tAA00000E /* Release */,
    \t\t\t);
    \t\t\tdefaultConfigurationIsVisible = 0;
    \t\t\tdefaultConfigurationName = Debug;
    \t\t};
    /* End XCConfigurationList section */
    \t};
    \trootObject = AA000009 /* Project object */;
    }
    """
  end

  defp macos?, do: match?({:unix, :darwin}, :os.type())
end
