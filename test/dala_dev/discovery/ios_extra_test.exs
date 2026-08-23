defmodule DalaDev.Discovery.IOSExtraTest do
  use ExUnit.Case, async: true

  alias DalaDev.Discovery.IOS

  describe "parse_simctl_json/1 — edge cases" do
    test "handles malformed JSON gracefully" do
      assert_raise Jason.DecodeError, fn ->
        IOS.parse_simctl_json("not json")
      end
    end

    test "skips devices missing udid" do
      json =
        ~s({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-18-0": [{"name": "NoUdid", "state": "Booted"}]}})

      assert IOS.parse_simctl_json(json) == []
    end
  end

  describe "parse_simctl_text/1 — edge cases" do
    test "ignores header and footer lines" do
      output = """
      == Devices ==
      -- iOS 18.0 --
          iPhone 17 (78354490-EF38-44D7-A437-DD941C20524D) (Booted)
      ==
      """

      devices = IOS.parse_simctl_text(output)
      assert length(devices) == 1
      assert hd(devices).name == "iPhone 17"
    end

    test "parses shutdown lines as empty" do
      output = "    iPad (11111111-2222-3333-4444-555555555555) (Shutdown)\n"
      assert IOS.parse_simctl_text(output) == []
    end
  end

  describe "parse_runtime_version/1 — full runtime key" do
    test "extracts version from full CoreSimulator key" do
      assert IOS.parse_runtime_version("com.apple.CoreSimulator.SimRuntime.iOS-18-2") ==
               "iOS 18.2"
    end
  end
end
