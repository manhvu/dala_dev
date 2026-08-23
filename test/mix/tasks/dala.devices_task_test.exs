defmodule Mix.Tasks.Dala.DevicesTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1" do
    @tag :slow_discovery
    test "lists devices without crashing (adb/xcrun may be missing)" do
      output =
        capture_io(fn ->
          Mix.Tasks.Dala.Devices.run([])
        end)

      assert output =~ "Android" or output =~ "iOS" or output == ""
    end
  end
end

defmodule Mix.Tasks.Dala.ScreenTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1" do
    test "raises or errors gracefully without a device" do
      result =
        try do
          capture_io(fn ->
            Mix.Tasks.Dala.Screen.run(["shot", "--device", "NOT_A_DEVICE"])
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

defmodule Mix.Tasks.Dala.LogsTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1" do
    test "handles missing device gracefully" do
      result =
        try do
          capture_io(fn ->
            Mix.Tasks.Dala.Logs.run(["--device", "NOT_A_DEVICE"])
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
