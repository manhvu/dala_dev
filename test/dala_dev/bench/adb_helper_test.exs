defmodule DalaDev.Bench.ADBHelperTest do
  use ExUnit.Case, async: false

  alias DalaDev.Bench.ADBHelper

  describe "available?/0" do
    test "returns true only when adb is on PATH" do
      expected = System.find_executable("adb") != nil
      assert ADBHelper.available?() == expected
    end
  end

  describe "check_device/1" do
    test "returns a tuple for nil (any device)" do
      result = ADBHelper.check_device(nil)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "returns error for bogus serial" do
      assert {:error, _} = ADBHelper.check_device("NOT_A_REAL_SERIAL_XYZ")
    end
  end

  describe "battery_level/1" do
    test "returns structured error for bogus serial" do
      assert {:error, msg} = ADBHelper.battery_level("NOT_A_REAL_SERIAL_XYZ")
      assert is_binary(msg) and byte_size(msg) > 0
      assert msg =~ "adb"
    end
  end

  describe "app_pid/2" do
    test "returns app_unknown/app_dead or pid for bogus serial" do
      result = ADBHelper.app_pid("NOT_A_REAL_SERIAL_XYZ", "com.example.app")
      assert match?(:app_unknown, result) or match?(:app_dead, result) or match?({:ok, _}, result)
    end
  end

  describe "device_ok?/1" do
    test "returns false for a nonexistent device struct" do
      device = %DalaDev.Device{platform: :android, serial: "NOT_A_REAL_SERIAL", type: :physical}
      assert ADBHelper.device_ok?(device) == false
    end
  end

  describe "wifi_ip/1" do
    test "returns error or ip for bogus serial" do
      result = ADBHelper.wifi_ip("NOT_A_REAL_SERIAL_XYZ")
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end
end
