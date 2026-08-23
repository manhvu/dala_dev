defmodule DalaDev.FileTransferDispatchTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias DalaDev.FileTransfer

  describe "push/3 with no devices" do
    test "returns error list when device filter matches nothing" do
      results = FileTransfer.push("/tmp/x.txt", "remote.txt", device: "DEFINITELY_NOT_A_DEVICE")
      assert [{:error, _}] = results
    end
  end

  describe "pull/3 with no devices" do
    test "returns error list when device filter matches nothing" do
      results = FileTransfer.pull("remote.txt", "/tmp/out.txt", device: "DEFINITELY_NOT_A_DEVICE")
      assert [{:error, _}] = results
    end
  end

  describe "sync/3 with no devices" do
    test "returns error list when device filter matches nothing" do
      results = FileTransfer.sync("/tmp/a", "remote", device: "DEFINITELY_NOT_A_DEVICE")
      assert [{:error, _}] = results
    end
  end

  describe "ls/2 with no devices" do
    test "returns error when device filter matches nothing" do
      result = FileTransfer.ls("Documents", device: "DEFINITELY_NOT_A_DEVICE")
      assert {:error, _} = result
    end
  end
end
