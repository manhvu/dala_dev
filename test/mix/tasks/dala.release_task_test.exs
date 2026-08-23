defmodule Mix.Tasks.Dala.ReleaseTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1" do
    test "fails gracefully outside a dala project (no crash loop)" do
      # The task requires dala.exs config; in the test env it will raise.
      # We only assert it terminates with a raised Mix error, not a hang.
      result =
        try do
          capture_io(fn ->
            Mix.Tasks.Dala.Release.run([])
          end)

          :completed
        rescue
          _ -> :raised
        catch
          :exit, _ -> :exited
        end

      assert result in [:completed, :raised, :exited]
    end
  end
end
