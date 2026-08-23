defmodule Mix.Tasks.Dala.BatteryBenchAndroidHelpersTest do
  # async: false — resolve_build_flags/1 names its tmp header dir with
  # second granularity (dala_bench_flags_<os_time(:second)>), shared with the
  # iOS bench helpers; concurrent same-second runs delete each other's dir.
  use ExUnit.Case, async: false

  describe "resolve_build_flags/1" do
    test "no_beam returns NO_BEAM define" do
      {flags, header_dir} = Mix.Tasks.Dala.BatteryBenchAndroid.resolve_build_flags(no_beam: true)
      assert flags == "-DNO_BEAM"
      assert is_nil(header_dir)
    end

    test "custom flags generate a header file" do
      {flags, header_dir} =
        Mix.Tasks.Dala.BatteryBenchAndroid.resolve_build_flags(flags: "--schedulers 2 +A 4")

      assert flags =~ "BEAM_USE_CUSTOM_FLAGS"
      assert flags =~ "-I"

      on_exit(fn -> File.rm_rf!(header_dir) end)

      header = File.read!(Path.join(header_dir, "dala_beam_flags.h"))
      assert header =~ "--schedulers"
      assert header =~ "+A"
      assert header =~ "BEAM_EXTRA_FLAGS"
    end

    test "preset untuned" do
      {flags, nil} = Mix.Tasks.Dala.BatteryBenchAndroid.resolve_build_flags(preset: "untuned")
      assert flags == "-DBEAM_UNTUNED"
    end

    test "preset sbwt" do
      {flags, nil} = Mix.Tasks.Dala.BatteryBenchAndroid.resolve_build_flags(preset: "sbwt")
      assert flags == "-DBEAM_SBWT_ONLY"
    end

    test "preset nerves" do
      {flags, nil} = Mix.Tasks.Dala.BatteryBenchAndroid.resolve_build_flags(preset: "nerves")
      assert flags == "-DBEAM_FULL_NERVES"
    end

    test "unknown preset raises" do
      assert catch_error(Mix.Tasks.Dala.BatteryBenchAndroid.resolve_build_flags(preset: "bogus"))
    end

    test "no options returns default empty flags" do
      {flags, nil} = Mix.Tasks.Dala.BatteryBenchAndroid.resolve_build_flags([])
      assert flags == ""
    end
  end

  describe "describe_mode/1" do
    test "no-beam mode" do
      assert Mix.Tasks.Dala.BatteryBenchAndroid.describe_mode(no_beam: true) ==
               "no-beam (baseline)"
    end

    test "custom flags mode" do
      assert Mix.Tasks.Dala.BatteryBenchAndroid.describe_mode(flags: "-S 2") ==
               "custom flags: -S 2"
    end

    test "preset mode" do
      assert Mix.Tasks.Dala.BatteryBenchAndroid.describe_mode(preset: "sbwt") == "preset: sbwt"
    end

    test "default mode" do
      assert Mix.Tasks.Dala.BatteryBenchAndroid.describe_mode([]) == "default (Nerves tuning)"
    end
  end
end
