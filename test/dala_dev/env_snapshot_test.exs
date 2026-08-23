# async: false — the fake-tools test mutates the process-global PATH.
defmodule DalaDev.EnvSnapshotTest do
  use ExUnit.Case, async: false

  alias DalaDev.EnvSnapshot

  describe "version parsers" do
    test "parse_adb_version/1" do
      output = """
      Android Debug Bridge version 1.0.41
      Version 34.0.5-11300000
      Installed as /usr/local/bin/adb
      """

      assert EnvSnapshot.parse_adb_version(output) == "34.0.5-11300000"
      assert EnvSnapshot.parse_adb_version("") == nil
      assert EnvSnapshot.parse_adb_version(nil) == nil

      # older adb prints a single banner line, lowercase "version"
      assert EnvSnapshot.parse_adb_version("Android Debug Bridge version 34.0.5\n") ==
               "34.0.5"
    end

    test "parse_xcrun_version/1" do
      assert EnvSnapshot.parse_xcrun_version("xcrun version 61.\n") == "61."

      assert EnvSnapshot.parse_xcrun_version("xcrun: error: invalid active developer path") ==
               nil

      assert EnvSnapshot.parse_xcrun_version(nil) == nil
    end
  end

  describe "parse_emulator_version/1" do
    test "skips INFO banner lines" do
      output = """
      INFO | Storing crash data in ...
      INFO | Loading emulators...
      Android emulator version 35.1.20.0 (build_id 123)
      """

      assert EnvSnapshot.parse_emulator_version(output) =~ "Android emulator version"
    end

    test "returns nil for empty or info-only output" do
      assert EnvSnapshot.parse_emulator_version("INFO | nothing\n") == nil
      assert EnvSnapshot.parse_emulator_version("") == nil
      assert EnvSnapshot.parse_emulator_version(nil) == nil
    end
  end

  describe "collect/0" do
    test "returns a JSON-encodable snapshot with the documented sections" do
      assert %{host: _, android: _, ios: _, project: _, devices: _} =
               snapshot =
               EnvSnapshot.collect()

      # host.os comes from :os.type(); elixir/otp mirror the running system
      assert snapshot.host.os in ["macOS", "linux", "Windows"]
      assert snapshot.host.elixir == System.version()
      assert snapshot.host.otp == System.otp_release()

      # Devices must be plain JSON-safe values.
      Enum.each(snapshot.devices, fn d ->
        assert d.platform in ["android", "ios"]
        assert is_integer(d.dist_port) and d.dist_port >= 9100
        assert "#{d.node}" =~ "@"
      end)
    end

    test "collect_json/0 produces valid JSON" do
      json = EnvSnapshot.collect_json()
      assert {:ok, decoded} = JSON.decode(json)
      assert Map.has_key?(decoded, "host")
    end

    @tag :fake_tools
    test "collect/0 reads versions and devices through the real tool plumbing" do
      fake = fake_toolchain_dir()

      on_exit(fn -> File.rm_rf(fake) end)

      original = System.get_env("PATH")
      System.put_env("PATH", "#{fake}:#{original}")

      try do
        snapshot = EnvSnapshot.collect()

        # fake adb prints both banner and Version line
        assert snapshot.android.adb == "41.0.0-9999999"
        # fake emulator prints INFO banners before the version line
        assert snapshot.android.emulator =~ "Android emulator version"
        # fake xcrun exits non-zero — must degrade to nil, not raise
        assert snapshot.host.developer_dir == "/Applications/Xcode.app/Contents/Developer"
        assert snapshot.ios.available == true
        assert snapshot.host.os in ["macOS", "linux", "Windows"]

        # the fake `adb devices -l` feeds one emulator through discovery,
        # exercising device_entries/0 end-to-end (id, node, dist port)
        assert [%{platform: "android", id: "emulator-9999"} = device] = snapshot.devices
        assert device.node == :"#{Mix.Project.config()[:app]}_android_fake12345@127.0.0.1"
        assert is_integer(device.dist_port)
      after
        restore_path(original)
      end
    end

    defp restore_path(nil), do: System.delete_env("PATH")
    defp restore_path(path), do: System.put_env("PATH", path)

    defp fake_toolchain_dir do
      dir = Path.join(System.tmp_dir!(), "dala_env_fake_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)

      # Responds to every adb subcommand discovery makes, including a full
      # `devices -l` listing with one emulator.
      adb_script = """
      #!/bin/sh
      case "$*" in
        *--version*)
          echo 'Android Debug Bridge version 1.0.41'
          echo 'Version 41.0.0-9999999'
          ;;
        *devices*)
          printf 'List of devices attached\\n'
          printf 'emulator-9999 device product:fake model:Pixel_Fake device:fake transport_id:1\\n'
          ;;
        *ro.product.model*) echo Pixel_Fake ;;
        *ro.build.version.release*) echo 15 ;;
        *ro.serialno*) echo FAKE12345 ;;
        *) echo "" ;;
      esac
      """

      write_bin(dir, "adb", adb_script)

      write_bin(
        dir,
        "emulator",
        "#!/bin/sh\necho 'INFO | Storing crashdata'\necho 'Android emulator version 35.1.20.0 (build_id 42)'\n"
      )

      write_bin(
        dir,
        "xcode-select",
        "#!/bin/sh\necho /Applications/Xcode.app/Contents/Developer\n"
      )

      # Exits non-zero with output on stdout → run/2's error arm.
      write_bin(dir, "xcrun", "#!/bin/sh\necho 'xcrun: error: no developer tools' >&2\nexit 1\n")

      for name <- ["adb", "emulator", "xcode-select", "xcrun"] do
        File.chmod!(Path.join(dir, name), 0o755)
      end

      dir
    end

    defp write_bin(dir, name, body) do
      File.write!(Path.join(dir, name), body)
    end
  end
end
