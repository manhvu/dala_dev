defmodule DalaDev.DeployerDeployAllTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias DalaDev.Deployer

  describe "deploy_all/1 — no-device paths" do
    @tag :slow_discovery
    test "returns empty lists when no devices found" do
      {deployed, failed} =
        Deployer.deploy_all(platforms: [:android, :ios], device: "NO_SUCH_DEVICE_XYZ")

      assert deployed == []
      assert failed == []
    end

    test "returns empty lists for a platform list with no devices" do
      {deployed, failed} = Deployer.deploy_all(platforms: [])
      assert deployed == []
      assert failed == []
    end

    test "prints a warning when no devices" do
      output =
        capture_io(fn ->
          Deployer.deploy_all(platforms: [])
        end)

      assert output =~ "No devices"
    end
  end

  describe "collect_beam_dirs/0 + count_beams/1" do
    test "collect_beam_dirs returns existing directories" do
      assert [first_dir | _] = dirs = Deployer.collect_beam_dirs()
      assert File.dir?(first_dir)
      Enum.each(dirs, &assert(File.dir?(&1)))
    end

    test "count_beams counts .beam files in dirs" do
      assert is_integer(Deployer.count_beams(Deployer.collect_beam_dirs()))
      assert Deployer.count_beams([]) == 0
      assert Deployer.count_beams(["/nonexistent"]) == 0
    end
  end
end
