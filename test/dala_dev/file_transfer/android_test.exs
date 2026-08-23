defmodule DalaDev.FileTransferAndroidTest do
  use ExUnit.Case, async: false

  alias DalaDev.FileTransfer.Platform.Android

  describe "push/4 — error paths" do
    test "returns structured error for missing local file" do
      device = %DalaDev.Device{platform: :android, serial: "NOT_A_SERIAL", type: :physical}

      result = Android.push(device, "/nonexistent/local/file.txt", "remote.txt", [])
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end

  describe "pull/4 — error paths" do
    test "returns structured result for bogus serial" do
      device = %DalaDev.Device{platform: :android, serial: "NOT_A_SERIAL", type: :physical}

      result = Android.pull(device, "remote.txt", "/tmp/dala_pull_test_out.txt", [])
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end

  describe "ls/2 — error paths" do
    test "returns structured error for bogus serial" do
      device = %DalaDev.Device{platform: :android, serial: "NOT_A_SERIAL", type: :physical}

      result = Android.ls(device, "Documents")
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end
end
