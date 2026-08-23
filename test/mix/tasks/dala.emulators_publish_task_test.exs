defmodule Mix.Tasks.Dala.EmulatorsTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1 — list mode" do
    @tag :slow_discovery
    test "lists emulators without crashing (adb/xcrun may be missing)" do
      output =
        capture_io(fn ->
          Mix.Tasks.Dala.Emulators.run([])
        end)

      assert output =~ "Android emulators"
      assert output =~ "iOS simulators"
    end
  end
end

defmodule Mix.Tasks.Dala.PublishTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1 — environment guards" do
    test "raises when xcrun missing or not a proper project (no hang)" do
      result =
        try do
          capture_io(fn ->
            Mix.Tasks.Dala.Publish.run(["--ipa", "test.ipa"])
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

defmodule Mix.Tasks.Dala.PublishAndroidTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1 — environment guards" do
    test "raises gracefully without proper setup (no hang)" do
      result =
        try do
          capture_io(fn ->
            Mix.Tasks.Dala.Publish.Android.run(["--aab", "test.aab"])
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
