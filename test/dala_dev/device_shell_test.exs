defmodule DalaDev.DeviceShellTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias DalaDev.DeviceShell

  describe "open_command/2" do
    test "android builds an interactive run-as shell" do
      assert {:shell, "adb -s emulator-5554 shell run-as com.example.app"} =
               DeviceShell.open_command({:android, "emulator-5554"}, "com.example.app")
    end

    test "ios simulator returns the container-path command" do
      assert {:dir, "xcrun simctl get_app_container UDID com.example.app data"} =
               DeviceShell.open_command({:ios_simulator, "UDID"}, "com.example.app")
    end

    test "physical ios is unsupported" do
      assert :unsupported = DeviceShell.open_command({:ios_physical, "UDID"}, "com.example.app")
    end
  end

  describe "exec_command/3" do
    test "android runs one-shot via run-as -c with quoting" do
      {:exec, cmd} =
        DeviceShell.exec_command(
          {:android, "serial-1"},
          "com.example.app",
          "ls -la files/"
        )

      assert cmd == ~s(adb -s serial-1 shell run-as com.example.app -c 'ls -la files/')
    end

    test "embedded single quotes are escaped for sh" do
      {:exec, cmd} = DeviceShell.exec_command({:android, "s"}, "com.a", "echo 'hi'")

      assert cmd == "adb -s s shell run-as com.a -c 'echo '\\''hi'\\'''"
    end

    test "ios simulator cds into the resolved container first" do
      {:exec, cmd} =
        DeviceShell.exec_command({:ios_simulator, "UDID"}, "com.example.app", "ls")

      assert cmd ==
               "cd \"$(xcrun simctl get_app_container UDID com.example.app data)\" && sh -c 'ls'"
    end

    test "physical ios is unsupported" do
      assert :unsupported = DeviceShell.exec_command({:ios_physical, "U"}, "com.a", "ls")
    end
  end

  describe "resolve_target/2 with injected devices" do
    @android %DalaDev.Device{platform: :android, serial: "emulator-5554", type: :emulator}
    @ios_sim %DalaDev.Device{platform: :ios, serial: "AAAACCCC-DDDD", type: :simulator}
    @phys %DalaDev.Device{platform: :ios, serial: "PHYSDUDID", type: :physical}

    test "nil id picks the first connected device (android)" do
      assert {:ok, {:android, "emulator-5554"}, label} =
               DeviceShell.resolve_target(nil, fn -> [@android] end)

      assert label == "emulator-5554"
    end

    test "maps ios simulators to the simulator target" do
      assert {:ok, {:ios_simulator, "AAAACCCC-DDDD"}, _} =
               DeviceShell.resolve_target("aaaacccc", fn -> [@ios_sim] end)
    end

    test "maps physical ios to the physical target" do
      assert {:ok, {:ios_physical, "PHYSDUDID"}, _} =
               DeviceShell.resolve_target(nil, fn -> [@phys] end)
    end

    test "filters unauthorized devices out" do
      bad = %DalaDev.Device{platform: :android, serial: "nope", status: :unauthorized}

      assert {:error, "no connected devices found"} =
               DeviceShell.resolve_target(nil, fn -> [bad] end)
    end

    test "reports unmatched ids" do
      assert {:error, reason} = DeviceShell.resolve_target("zzz", fn -> [@android] end)
      assert reason == ~s(no device matched "zzz")
    end
  end

  describe "run/1" do
    test "returns 0 for a successful command" do
      assert DeviceShell.run("true") == 0
    end

    test "propagates non-zero exit status" do
      {status, _output} = with_io(fn -> DeviceShell.run("exit 7") end)
      assert status == 7
    end
  end

  describe "resolve_target/1" do
    test "returns a structured error when nothing matches" do
      assert {:error, reason} = DeviceShell.resolve_target("NOPE_NOT_A_DEVICE")
      assert reason =~ "no device matched"
    end
  end
end
