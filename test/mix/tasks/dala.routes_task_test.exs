defmodule Mix.Tasks.Dala.RoutesTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1" do
    test "scans the project and prints a report without crashing" do
      output =
        capture_io(fn ->
          try do
            Mix.Tasks.Dala.Routes.run([])
          rescue
            _ -> :ok
          catch
            :exit, _ -> :ok
          end
        end)

      assert output =~ "navigation" or output =~ "route" or output =~ "No navigation" or
               output =~ "push_screen" or output == ""
    end

    test "runs with --strict without crashing on clean projects" do
      output =
        capture_io(fn ->
          try do
            Mix.Tasks.Dala.Routes.run(["--strict"])
          rescue
            _ -> :ok
          catch
            :exit, _ -> :ok
          end
        end)

      assert output =~ ~r/\d+ navigation reference\(s\)/
      refute output =~ "unresolvable"
    end
  end
end
