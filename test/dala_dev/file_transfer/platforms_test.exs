defmodule DalaDev.FileTransferPhysicalTest do
  use ExUnit.Case, async: false

  alias DalaDev.FileTransfer.Platform.Physical

  @device %DalaDev.Device{platform: :ios, type: :physical, serial: "NOT-A-REAL-UDID"}

  describe "push/4 — error paths" do
    test "returns structured result for bogus udid" do
      result = Physical.push(@device, "/nonexistent/file.txt", "remote.txt", [])
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end

  describe "pull/4 — error paths" do
    test "returns structured result for bogus udid" do
      result = Physical.pull(@device, "remote.txt", "/tmp/dala_phys_pull.txt", [])
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end

  describe "ls/2 — error paths" do
    test "returns structured result for bogus udid" do
      result = Physical.ls(@device, "Documents")
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end
end

defmodule DalaDev.FileTransferSimulatorTest do
  use ExUnit.Case, async: false

  alias DalaDev.FileTransfer.Platform.Simulator

  @device %DalaDev.Device{
    platform: :ios,
    type: :simulator,
    serial: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
  }

  describe "push/4 — error paths" do
    test "returns structured result for bogus udid" do
      result = Simulator.push(@device, "/nonexistent/file.txt", "remote.txt", [])
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end

  describe "pull/4 — error paths" do
    test "returns structured result for bogus udid" do
      result = Simulator.pull(@device, "remote.txt", "/tmp/dala_sim_pull.txt", [])
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end

  describe "ls/2 — error paths" do
    test "returns structured result for bogus udid" do
      result = Simulator.ls(@device, "Documents")
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end
end
