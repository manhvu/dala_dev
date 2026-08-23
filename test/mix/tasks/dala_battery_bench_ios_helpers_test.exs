defmodule Mix.Tasks.Dala.BatteryBenchIosHelpersTest do
  # async: false — resolve_build_flags/1 names its tmp header dir with
  # second granularity (dala_bench_flags_<os_time(:second)>), shared with the
  # Android bench helpers; concurrent same-second runs delete each other's dir.
  use ExUnit.Case, async: false

  describe "resolve_build_flags/1" do
    test "no_beam returns NO_BEAM define" do
      {flags, header_dir} = Mix.Tasks.Dala.BatteryBenchIos.resolve_build_flags(no_beam: true)
      assert flags == "-DNO_BEAM"
      assert is_nil(header_dir)
    end

    test "custom flags generate a header file" do
      {flags, header_dir} =
        Mix.Tasks.Dala.BatteryBenchIos.resolve_build_flags(flags: "--schedulers 2")

      assert flags =~ "BEAM_USE_CUSTOM_FLAGS"

      on_exit(fn -> File.rm_rf!(header_dir) end)

      header = File.read!(Path.join(header_dir, "dala_beam_flags.h"))
      assert header =~ "--schedulers"
    end

    test "presets resolve to defines" do
      for {preset, expected} <- [
            {"untuned", "-DBEAM_UNTUNED"},
            {"sbwt", "-DBEAM_SBWT_ONLY"},
            {"nerves", "-DBEAM_FULL_NERVES"}
          ] do
        {flags, nil} = Mix.Tasks.Dala.BatteryBenchIos.resolve_build_flags(preset: preset)
        assert flags == expected
      end
    end

    test "unknown preset raises" do
      assert catch_error(Mix.Tasks.Dala.BatteryBenchIos.resolve_build_flags(preset: "bogus"))
    end

    test "default returns empty flags" do
      {flags, nil} = Mix.Tasks.Dala.BatteryBenchIos.resolve_build_flags([])
      assert flags == ""
    end
  end

  describe "describe_mode/1" do
    test "all modes" do
      assert Mix.Tasks.Dala.BatteryBenchIos.describe_mode(no_beam: true) == "no-beam (baseline)"
      assert Mix.Tasks.Dala.BatteryBenchIos.describe_mode(flags: "-S 1") == "custom flags: -S 1"
      assert Mix.Tasks.Dala.BatteryBenchIos.describe_mode(preset: "untuned") == "preset: untuned"
      assert Mix.Tasks.Dala.BatteryBenchIos.describe_mode([]) == "default (Nerves tuning)"
    end
  end

  describe "node_matches_prefix?/2 — extra cases" do
    test "matches longnames with IP host part" do
      assert Mix.Tasks.Dala.BatteryBenchIos.node_matches_prefix?(
               :"test_nif_ios@10.0.0.5",
               "test_nif"
             )
    end
  end
end
