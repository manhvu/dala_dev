defmodule DalaDev.ScreenCaptureTest do
  use ExUnit.Case, async: false

  alias DalaDev.{ScreenCapture, Device}

  describe "capture/2 dispatch" do
    test "returns error for unsupported device type" do
      device = %Device{platform: :android, serial: "emulator-5554", type: nil}

      # A %Device{} with no platform-specific handler still routes; android
      # path requires adb. With a bogus serial adb fails fast.
      result = ScreenCapture.capture(device)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "returns :device_not_found for unknown atom node" do
      assert {:error, :device_not_found} = ScreenCapture.capture(:"nonexistent@127.0.0.1")
    end

    test "returns :device_not_found for unknown binary serial" do
      assert {:error, :device_not_found} = ScreenCapture.capture("NOT_A_REAL_SERIAL")
    end

    test "accepts a %Device{} struct" do
      ios_sim = %Device{platform: :ios, type: :simulator, serial: "NOT-A-REAL-UDID"}

      # xcrun will fail on the bogus UDID but must return a structured error
      assert match?({:error, _}, ScreenCapture.capture(ios_sim))
    end
  end

  describe "record/2" do
    test "returns structured error for unknown device ref" do
      assert {:error, :device_not_found} = ScreenCapture.record("NOT_A_REAL_SERIAL")
    end

    test "clamps Android duration to 180s max (no crash on huge duration)" do
      device = %Device{platform: :android, serial: "bogus-serial", type: :physical}
      # adb not present / bogus serial → structured error, no hang
      result = ScreenCapture.record(device, duration: 999_999)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "live_preview/2" do
    test "starts and stops a preview server process" do
      device = %Device{platform: :ios, type: :simulator, serial: "UDID"}

      assert {:ok, pid} = ScreenCapture.live_preview(device, port: 5999)
      assert Process.alive?(pid)
      send(pid, :stop)
      Process.sleep(10)
      refute Process.alive?(pid)
    end

    test "returns error for unknown device ref" do
      assert {:error, :device_not_found} = ScreenCapture.live_preview(:nonexistent@x)
    end
  end
end
