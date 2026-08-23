defmodule DalaDev.Discovery.AndroidTest do
  use ExUnit.Case, async: true

  alias DalaDev.Device
  alias DalaDev.Discovery.Android

  describe "parse_devices_output/1" do
    test "parses a physical device line with product info" do
      output = """
      List of devices attached
      R5CW3089HVB            device product:star2q model:SM-G991B device:r0s
      """

      assert [%Device{platform: :android, serial: "R5CW3089HVB", type: :physical, status: :discovered}] =
               Android.parse_devices_output(output)
    end

    test "parses an emulator as type :emulator" do
      output = """
      List of devices attached
      emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64
      """

      assert [%Device{serial: "emulator-5554", type: :emulator, status: :discovered}] =
               Android.parse_devices_output(output)
    end

    test "marks unauthorized devices with error message" do
      output = """
      List of devices attached
      ABC123                 unauthorized usb:123456X
      """

      assert [%Device{status: :unauthorized} = dev] = Android.parse_devices_output(output)
      assert dev.serial == "ABC123"
      assert dev.error =~ "USB debugging not authorized"
    end

    test "skips offline devices" do
      output = """
      List of devices attached
      XYZ789                 offline
      emulator-5554          device
      """

      devices = Android.parse_devices_output(output)
      assert length(devices) == 1
      assert hd(devices).serial == "emulator-5554"
    end

    test "handles WiFi-adb serials (ip:port)" do
      output = """
      List of devices attached
      192.168.1.5:5555       device
      """

      assert [%Device{serial: "192.168.1.5:5555", type: :physical}] =
               Android.parse_devices_output(output)
    end

    test "rejects blank lines and unknown states" do
      output = """
      List of devices attached

      ABC                    recovery

      DEF                    device
      """

      serials = Android.parse_devices_output(output) |> Enum.map(& &1.serial)
      assert serials == ["DEF"]
    end

    test "returns empty list for header only" do
      assert Android.parse_devices_output("List of devices attached\n") == []
    end

    test "handles 'no permissions' state as discovered" do
      output = """
      List of devices attached
      BADSERIAL              no permissions (user in plugdev group)
      """

      assert [%Device{serial: "BADSERIAL", status: :discovered}] =
               Android.parse_devices_output(output)
    end

    test "rejects lines with leading whitespace (empty serial)" do
      output = "List of devices attached\n   emulator-5556    device product:x"

      assert Android.parse_devices_output(output) == []
    end
  end

  describe "node_suffix_for/1" do
    test "lowercases and keeps alphanumerics" do
      assert Android.node_suffix_for("ZY22CRLMWK") == "zy22crlmwk"
    end

    test "strips WiFi-adb port suffix" do
      assert Android.node_suffix_for("10.0.0.82:5555") == "10_0_0_82"
    end

    test "replaces dashes with underscores" do
      assert Android.node_suffix_for("emulator-5554") == "emulator_5554"
    end

    test "collapses runs of non-alphanumerics into a single underscore" do
      assert Android.node_suffix_for("a--b..c") == "a_b_c"
    end

    test "trims leading and trailing underscores" do
      assert Android.node_suffix_for("--abc--") == "abc"
    end
  end
end
