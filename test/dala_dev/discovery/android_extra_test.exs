defmodule DalaDev.Discovery.AndroidExtraTest do
  use ExUnit.Case, async: true

  alias DalaDev.Discovery.Android

  describe "node_suffix_for/1 — extra cases" do
    test "strips wifi-adb port" do
      assert Android.node_suffix_for("10.0.0.17:5555") == "10_0_0_17"
    end

    test "lowercases and sanitizes hardware serials" do
      assert Android.node_suffix_for("ZY22-K6BSJM") == "zy22_k6bsjm"
    end

    test "emulator serial stays intact" do
      assert Android.node_suffix_for("emulator-5554") == "emulator_5554"
    end

    test "collapses runs of non-alphanumerics to a single underscore" do
      assert Android.node_suffix_for("a---b___c d") == "a_b_c_d"
    end
  end

  describe "parse_devices_output/1 — extra cases" do
    test "parses unauthorized device without enrichment crash" do
      output = """
      List of devices attached
      ABC123	unauthorized usb:1-1
      """

      devices = Android.parse_devices_output(output)
      assert length(devices) == 1
      assert hd(devices).status == :unauthorized
    end

    test "skips offline devices" do
      output = """
      List of devices attached
      DEADBEEF	offline
      """

      assert Android.parse_devices_output(output) == []
    end

    test "handles empty device list" do
      assert Android.parse_devices_output("List of devices attached\n") == []
      assert Android.parse_devices_output("") == []
    end

    test "parses wifi-adb device with ip:port serial" do
      output = """
      List of devices attached
      192.168.1.50:5555	device product:wifi
      """

      devices = Android.parse_devices_output(output)
      assert length(devices) == 1
      assert hd(devices).serial == "192.168.1.50:5555"
    end
  end

  describe "developer_mode/1" do
    test "returns any structured result for bogus serial without crashing" do
      # adb missing or bogus serial — must not raise; shape varies by env
      result = Android.developer_mode("NOT_A_SERIAL")
      assert result in [:enabled, :disabled, :unknown]
    end
  end
end
