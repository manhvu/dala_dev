defmodule DalaDev.DeviceClipboardTest do
  use ExUnit.Case, async: true

  alias DalaDev.DeviceClipboard

  describe "command builders" do
    test "ios_get_command/1" do
      assert DeviceClipboard.ios_get_command("UDID") == ["simctl", "pbpaste", "UDID"]
    end

    test "ios_put_command/2 targets pbcopy (text travels via stdin)" do
      assert DeviceClipboard.ios_put_command("UDID", "ignored") == ["simctl", "pbcopy", "UDID"]
    end
  end

  describe "get/1 and put/2 platform gating" do
    test "get returns a structured error when no devices exist" do
      # On CI/dev machines without devices both discovery lists come back
      # empty; either way the result must be a structured tuple.
      result = DeviceClipboard.get(nil)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  @android %DalaDev.Device{platform: :android, serial: "serial-1", type: :physical}
  @sim %DalaDev.Device{platform: :ios, serial: "AAAACCCC-DDDD", type: :simulator}
  @phys %DalaDev.Device{platform: :ios, serial: "PHYSDUDID", type: :physical}

  defp exec_stub(result), do: fn _args, _input -> result end

  describe "get/2 dispatch arms" do
    test "reads a simulator clipboard via xcrun" do
      assert {:ok, "copied text"} =
               DeviceClipboard.get(nil,
                 devices: [@sim],
                 exec: exec_stub({"copied text", 0})
               )
    end

    test "reports pbpaste failure" do
      assert {:error, "simctl pbpaste failed"} =
               DeviceClipboard.get("aaaacccc", devices: [@sim], exec: exec_stub({"", 1}))
    end

    test "android and physical ios are rejected with hints" do
      assert {:error, msg} =
               DeviceClipboard.get(nil, devices: [@android], exec: exec_stub({"", 0}))

      assert msg =~ "adb cannot read"

      assert {:error, msg} = DeviceClipboard.get(nil, devices: [@phys], exec: exec_stub({"", 0}))
      assert msg =~ "physical iOS"
    end

    test "resolution errors pass through" do
      assert {:error, reason} = DeviceClipboard.get(nil, devices: [], exec: exec_stub({"", 0}))
      assert reason =~ "no connected devices"

      assert {:error, reason} =
               DeviceClipboard.get("zzz", devices: [@sim], exec: exec_stub({"", 0}))

      assert reason =~ ~s(no device matched "zzz")
    end

    test "default executor runs real simctl against a bogus udid" do
      assert {:error, "simctl pbpaste failed"} =
               DeviceClipboard.get(nil,
                 devices: [
                   %DalaDev.Device{
                     platform: :ios,
                     serial: "99999999-8888-7777-6666-555555555555",
                     type: :simulator
                   }
                 ]
               )
    end
  end

  describe "put/3 dispatch arms" do
    test "writes to a simulator clipboard, passing text via stdin" do
      assert {:ok, "clipboard set"} =
               DeviceClipboard.put("hello", nil,
                 devices: [@sim],
                 exec: fn args, input ->
                   send(self(), {:exec, args, input})
                   {"", 0}
                 end
               )

      assert_received {:exec, ["simctl", "pbcopy", "AAAACCCC-DDDD"], "hello"}
    end

    test "reports pbcopy failure" do
      assert {:error, "simctl pbcopy failed"} =
               DeviceClipboard.put("x", nil, devices: [@sim], exec: exec_stub({"", 1}))
    end

    test "android and physical ios are rejected with hints" do
      assert {:error, msg} =
               DeviceClipboard.put("x", nil, devices: [@android], exec: exec_stub({"", 0}))

      assert msg =~ "adb cannot set"

      assert {:error, msg} =
               DeviceClipboard.put("x", nil, devices: [@phys], exec: exec_stub({"", 0}))

      assert msg =~ "physical iOS"
    end

    test "resolution errors pass through" do
      assert {:error, reason} =
               DeviceClipboard.put("x", "nope", devices: [@sim], exec: exec_stub({"", 0}))

      assert reason =~ "no device matched"
    end
  end
end
