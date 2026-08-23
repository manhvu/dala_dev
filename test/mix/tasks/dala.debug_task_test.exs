defmodule Mix.Tasks.Dala.DebugTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1 — one-shot modes" do
    test "--memory mode runs against the local node" do
      output =
        capture_io(fn ->
          Mix.Tasks.Dala.Debug.run(["--memory"])
        end)

      assert output =~ "Memory" or output =~ "memory" or output =~ "KB"
    end

    test "--tree mode runs against the local node" do
      output =
        capture_io(fn ->
          Mix.Tasks.Dala.Debug.run(["--tree"])
        end)

      assert output =~ "Supervision Tree:"
      assert output =~ "supervisors"
    end

    test "--eval mode evaluates code locally" do
      output =
        capture_io(fn ->
          Mix.Tasks.Dala.Debug.run(["--eval", "1 + 2"])
        end)

      assert output =~ "Result:"
      assert output =~ ~r/\b3\b/
    end
  end
end
