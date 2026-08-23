defmodule DalaDev.DeepLinkTest do
  use ExUnit.Case, async: true

  alias DalaDev.DeepLink

  describe "valid_url?/1" do
    test "accepts https and custom app schemes" do
      assert DeepLink.valid_url?("https://example.com/path?q=1")
      assert DeepLink.valid_url?("myapp://product/42")
      assert DeepLink.valid_url?("dala-demo://settings")
    end

    test "rejects scheme-less strings and non-strings" do
      refute DeepLink.valid_url?("example.com")
      refute DeepLink.valid_url?("just some words")
      refute DeepLink.valid_url?("")
      refute DeepLink.valid_url?(nil)
      refute DeepLink.valid_url?(42)
    end
  end

  describe "command builders" do
    test "android_open_command/2" do
      assert DeepLink.android_open_command("serial1", "https://x.dev") == [
               "-s",
               "serial1",
               "shell",
               "am",
               "start",
               "-a",
               "android.intent.action.VIEW",
               "-d",
               "https://x.dev"
             ]
    end

    test "ios_open_command/2" do
      assert DeepLink.ios_open_command("UDID", "myapp://home") == [
               "simctl",
               "openurl",
               "UDID",
               "myapp://home"
             ]
    end
  end

  describe "open/2 validation" do
    test "raises on scheme-less input before touching any device" do
      assert_raise ArgumentError, ~r/not a routable URL/, fn ->
        DeepLink.open("not-a-url")
      end
    end
  end

  @android %DalaDev.Device{
    platform: :android,
    serial: "emulator-5554",
    type: :emulator,
    name: "Pixel"
  }
  @sim %DalaDev.Device{platform: :ios, serial: "AAAACCCC-DDDD", type: :simulator, name: "iPhone"}
  @phys %DalaDev.Device{platform: :ios, serial: "PHYSDUDID", type: :physical}

  describe "open_devices/3 dispatch arms" do
    test "adb success and failure" do
      ok =
        DeepLink.open_devices([@android], "myapp://x", exec: fn {:adb, _} -> {:ok, ""} end)

      assert [{"Pixel", {:ok, "opened myapp://x"}}] = ok

      fail =
        DeepLink.open_devices([@android], "myapp://x",
          exec: fn {:adb, _} -> {:error, :timeout} end
        )

      assert [{"Pixel", {:error, ":timeout"}}] = fail
    end

    test "xcrun success and failure on simulators" do
      ok =
        DeepLink.open_devices([@sim], "https://x.dev", exec: fn {:xcrun, _} -> {:ok, ""} end)

      assert [{"iPhone", {:ok, "opened https://x.dev"}}] = ok

      fail =
        DeepLink.open_devices([@sim], "https://x.dev",
          exec: fn {:xcrun, _} -> {:error, "Invalid device"} end
        )

      assert [{"iPhone", {:error, reason}}] = fail
      assert reason =~ "Invalid device"
    end

    test "physical iOS is unsupported" do
      [result] =
        DeepLink.open_devices([@phys], "https://x.dev", exec: fn _ -> flunk("never runs") end)

      assert {_, {:error, reason}} = result
      assert reason =~ "physical"
    end

    test "labels fall back to the serial when no name" do
      anon = %{@android | name: nil}
      [result] = DeepLink.open_devices([anon], "u://v", exec: fn _ -> {:ok, ""} end)
      assert {"emulator-5554", {:ok, _}} = result
    end
  end

  describe "default executor (no :exec opt)" do
    # Injected devices; the real adb/xcrun calls against bogus IDs fail fast.
    test "adb and xcrun failures surface as structured errors" do
      results =
        DeepLink.open_devices(
          [
            %DalaDev.Device{platform: :android, serial: "BOGUS_ADB_SERIAL", type: :physical},
            %DalaDev.Device{
              platform: :ios,
              serial: "00000000-0000-0000-0000-000000000000",
              type: :simulator
            }
          ],
          "myapp://x",
          []
        )

      assert [{_, {:error, _}}, {_, {:error, _}}] = results
    end
  end

  describe "open/2 with injected devices" do
    test "skips unauthorized devices and honors the --device filter" do
      unauthorized = %DalaDev.Device{platform: :android, serial: "nope", status: :unauthorized}

      results =
        DeepLink.open("myapp://home",
          devices: [unauthorized, @sim],
          exec: fn _ -> {:ok, ""} end
        )

      assert length(results) == 1

      filtered =
        DeepLink.open("myapp://home",
          devices: [@android, @sim],
          device: "aaaacccc",
          exec: fn _ -> {:ok, ""} end
        )

      assert [{_, {:ok, _}}] = filtered
    end
  end
end
