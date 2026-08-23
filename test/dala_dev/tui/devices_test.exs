defmodule DalaDev.Tui.DevicesTest do
  use ExUnit.Case, async: true

  describe "from_device/1" do
    test "maps an iOS simulator device struct" do
      device = %DalaDev.Device{
        platform: :ios,
        serial: "80F58DB6-1E8A-4CBF-8006-85358A38A57C",
        name: "iPhone 17 Pro",
        version: "iOS 26.4",
        type: :simulator,
        status: :discovered
      }

      entry = DalaDev.Tui.Devices.from_device(device)

      assert entry.id == "80F58DB6-1E8A-4CBF-8006-85358A38A57C"
      assert entry.platform == :ios
      assert entry.type == :simulator
      assert entry.name == "iPhone 17 Pro"
      assert entry.serial == "80F58DB6-1E8A-4CBF-8006-85358A38A57C"
      assert entry.version == "iOS 26.4"
      assert entry.status == :discovered
      assert entry.device_struct == device
    end

    test "maps an Android physical device with node metadata" do
      device = %DalaDev.Device{
        platform: :android,
        serial: "R5CW3089HVB",
        name: "Pixel 8",
        version: "Android 15",
        type: :physical,
        status: :connected,
        node: :"dala_app_android_r5cw3089hvb@127.0.0.1",
        dist_port: 9100,
        host_ip: "192.168.1.7"
      }

      entry = DalaDev.Tui.Devices.from_device(device)

      assert entry.id == "R5CW3089HVB"
      assert entry.type == :physical
      assert entry.status == :connected
      assert entry.node == :"dala_app_android_r5cw3089hvb@127.0.0.1"
      assert entry.dist_port == 9100
      assert entry.host_ip == "192.168.1.7"
    end

    test "falls back when name and type are missing" do
      device = %DalaDev.Device{platform: :android, serial: "emulator-5554"}
      entry = DalaDev.Tui.Devices.from_device(device)

      assert entry.name == "emulator-5554"
      assert entry.type == :device
      assert entry.status == :discovered
    end
  end

  describe "summary/1" do
    test "includes platform icon, display name, and status" do
      device = %DalaDev.Tui.Devices{
        id: "abc",
        platform: :ios,
        type: :simulator,
        name: "iPhone 17 Pro",
        status: :booted,
        serial: "abc"
      }

      summary = DalaDev.Tui.Devices.summary(device)

      assert summary =~ "🍎"
      assert summary =~ "iPhone 17 Pro (simulator)"
      assert summary =~ "booted"
    end
  end
end
