defmodule DalaDev.Discovery.IOSTest do
  use ExUnit.Case, async: true

  alias DalaDev.Device
  alias DalaDev.Discovery.IOS

  @udid "78354490-EF38-44D7-A437-DD941C20524D"

  describe "parse_simctl_json/1" do
    test "parses booted simulators with runtime version" do
      json = ~s({"devices" : {"com.apple.CoreSimulator.SimRuntime.iOS-18-0" : [
        {"udid" : "#{@udid}", "name" : "iPhone 17", "state" : "Booted"},
        {"udid" : "11111111-2222-3333-4444-555555555555", "name" : "iPad", "state" : "Shutdown"}
      ]}})

      assert [%Device{} = dev] = IOS.parse_simctl_json(json)
      assert dev.serial == @udid
      assert dev.name == "iPhone 17"
      assert dev.type == :simulator
      assert dev.status == :booted
      assert dev.version == "iOS 18.0"
    end

    test "skips non-booted simulators" do
      json = ~s({"devices" : {"com.apple.CoreSimulator.SimRuntime.iOS-17-5" : [
        {"udid" : "AAAA-BBBB", "name" : "Off", "state" : "Shutdown"}
      ]}})

      assert IOS.parse_simctl_json(json) == []
    end

    test "returns empty list when no devices key" do
      assert IOS.parse_simctl_json(~s({})) == []
    end

    test "handles multiple runtimes" do
      json = ~s({"devices" : {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-0" : [
          {"udid" : "#{@udid}", "name" : "A", "state" : "Booted"}
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-17-0" : [
          {"udid" : "99999999-0000-0000-0000-000000000000", "name" : "B", "state" : "Booted"}
        ]
      }})

      assert length(IOS.parse_simctl_json(json)) == 2
    end
  end

  describe "parse_simctl_text/1" do
    test "parses booted lines" do
      output = """
      == Devices ==
      -- iOS 18.0 --
          iPhone 17 (#{@udid}) (Booted)
          iPhone SE (AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE) (Shutdown)
      """

      assert [%Device{} = dev] = IOS.parse_simctl_text(output)
      assert dev.serial == @udid
      assert dev.name == "iPhone 17"
      assert dev.status == :booted
      assert dev.type == :simulator
    end

    test "returns empty for no booted devices" do
      output = """
      == Devices ==
          iPhone 17 (#{@udid}) (Shutdown)
      """

      assert IOS.parse_simctl_text(output) == []
    end
  end

  describe "parse_runtime_version/1" do
    test "parses standard runtime keys" do
      assert IOS.parse_runtime_version("com.apple.CoreSimulator.SimRuntime.iOS-18-0") ==
               "iOS 18.0"

      assert IOS.parse_runtime_version("com.apple.CoreSimulator.SimRuntime.iOS-17-5") ==
               "iOS 17.5"
    end

    test "falls back to last segment replacement for unknown keys" do
      assert IOS.parse_runtime_version("com.apple.CoreSimulator.SimRuntime.xrOS-1-2") ==
               "xrOS.1.2"
    end
  end
end
