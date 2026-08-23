defmodule DalaDev.NativeBuildAllDevicesTest do
  use ExUnit.Case, async: true

  alias DalaDev.NativeBuild

  describe "ios_build_targets/1" do
    test "no toolchain means no targets, regardless of everything else" do
      assert [] =
               NativeBuild.ios_build_targets(%{
                 toolchain: false,
                 sim_script: true,
                 physical_udid: "UDID",
                 all_devices: true
               })
    end

    test "explicit physical device targets only the device (default)" do
      assert [:physical] =
               NativeBuild.ios_build_targets(%{
                 toolchain: true,
                 sim_script: true,
                 physical_udid: "UDID",
                 all_devices: false
               })
    end

    test "--all builds both device and simulator when both are available" do
      assert [:physical, :sim] =
               NativeBuild.ios_build_targets(%{
                 toolchain: true,
                 sim_script: true,
                 physical_udid: "UDID",
                 all_devices: true
               })

      # No sim script → device only.
      assert [:physical] =
               NativeBuild.ios_build_targets(%{
                 toolchain: true,
                 sim_script: false,
                 physical_udid: "UDID",
                 all_devices: true
               })
    end

    test "no physical connected falls back to the simulator" do
      assert [:sim] =
               NativeBuild.ios_build_targets(%{
                 toolchain: true,
                 sim_script: true,
                 physical_udid: nil,
                 all_devices: false
               })

      # --all without any physical still just builds the sim.
      assert [:sim] =
               NativeBuild.ios_build_targets(%{
                 toolchain: true,
                 sim_script: true,
                 physical_udid: nil,
                 all_devices: true
               })
    end

    test "nothing available yields no targets" do
      assert [] =
               NativeBuild.ios_build_targets(%{
                 toolchain: true,
                 sim_script: false,
                 physical_udid: nil,
                 all_devices: true
               })
    end
  end
end
