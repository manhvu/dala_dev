defmodule DalaDev.NativeBuildExtraTest do
  use ExUnit.Case, async: true

  alias DalaDev.NativeBuild

  describe "__resolve_elixir_lib__/1" do
    test "returns the configured path when it exists" do
      # The current elixir install always exists
      existing = :code.lib_dir(:elixir) |> to_string() |> Path.dirname()
      assert NativeBuild.__resolve_elixir_lib__(existing) == existing
    end

    test "falls back to detected dir when configured path doesn't exist" do
      result = NativeBuild.__resolve_elixir_lib__("/nonexistent/elixir/lib")
      assert result == :code.lib_dir(:elixir) |> to_string() |> Path.dirname()
    end

    test "falls back to detected elixir lib dir for non-binary config" do
      result = NativeBuild.__resolve_elixir_lib__(nil)
      assert result == :code.lib_dir(:elixir) |> to_string() |> Path.dirname()
    end
  end

  describe "detect_physical_ios/0" do
    test "returns a UDID string or nil without crashing" do
      result = NativeBuild.detect_physical_ios()
      assert is_binary(result) or is_nil(result)
    end
  end

  describe "narrow_platforms_for_device/3 — physical udid format fallback" do
    defp no_devices, do: fn -> [] end

    test "40-char hex UDID narrows to ios even when offline" do
      udid = "ABCDEF0123456789ABCDEF0123456789ABCDEF01"

      assert NativeBuild.narrow_platforms_for_device([:android, :ios], udid, no_devices()) ==
               [:ios]
    end

    test "short-form UDID (8-16 hex) narrows to ios even when offline" do
      udid = "00008101-001A2B3C4D5E6F7E"

      assert NativeBuild.narrow_platforms_for_device([:android, :ios], udid, no_devices()) ==
               [:ios]
    end

    test "android-style serial narrows to android" do
      assert NativeBuild.narrow_platforms_for_device(
               [:android, :ios],
               "emulator-5554",
               no_devices()
             ) ==
               [:android]
    end

    test "nil device id keeps all platforms" do
      assert NativeBuild.narrow_platforms_for_device([:android, :ios], nil, no_devices()) ==
               [:android, :ios]
    end

    test "simulator device in discovery list narrows to ios" do
      sim = %DalaDev.Device{platform: :ios, type: :simulator, serial: "ABCD1234-5678-90EF"}

      lister = fn -> [sim] end

      assert NativeBuild.narrow_platforms_for_device([:android, :ios], "abcd1234", lister) == [
               :ios
             ]
    end

    test "physical device in discovery list narrows to ios" do
      phys = %DalaDev.Device{platform: :ios, type: :physical, serial: "PHYSICALUDID123"}

      lister = fn -> [phys] end

      assert NativeBuild.narrow_platforms_for_device([:android, :ios], "PHYSICALUDID123", lister) ==
               [:ios]
    end
  end

  describe "filter_serials/2 — port stripping" do
    test "strips :5555 from wifi-adb serials when matching bare IP" do
      assert NativeBuild.filter_serials(["192.168.1.5:5555"], "192.168.1.5") == [
               "192.168.1.5:5555"
             ]
    end

    test "matches full IP:port form" do
      assert NativeBuild.filter_serials(["192.168.1.5:5555"], "192.168.1.5:5555") == [
               "192.168.1.5:5555"
             ]
    end
  end

  describe "otp_dir_for_abi/3 edge cases" do
    test "x86 abi falls back to arm64" do
      assert NativeBuild.otp_dir_for_abi("x86", "/arm64", "/arm32") == "/arm64"
    end
  end
end
