defmodule Mix.Tasks.Dala.DeployDryRunTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1 --dry-run" do
    test "prints what would be deployed without deploying" do
      output =
        capture_io(fn ->
          Mix.Tasks.Dala.Deploy.run(["--dry-run", "--no-native"])
        end)

      assert output =~ "Dry run"
      # Either devices found or a warning — both are valid dry-run outcomes
      assert output =~ "would deploy to" or output =~ "No devices"
    end

    test "dry run with device filter prints filter result" do
      output =
        capture_io(fn ->
          Mix.Tasks.Dala.Deploy.run(["--dry-run", "--device", "NOT_A_DEVICE"])
        end)

      assert output =~ "Dry run"
    end
  end

  describe "run/1 --quiet suppresses info output" do
    test "quiet mode runs without step headers" do
      output =
        capture_io(fn ->
          Mix.Tasks.Dala.Deploy.run(["--dry-run", "--quiet"])
        end)

      refute output =~ "==>"
    end
  end
end
