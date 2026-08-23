defmodule Mix.Tasks.Dala.DoctorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1" do
    test "runs all checks and prints a report without crashing" do
      output =
        capture_io(fn ->
          try do
            Mix.Tasks.Dala.Doctor.run([])
          rescue
            # Mix.raise at the end when failures exist is expected in CI envs
            _ -> :ok
          end
        end)

      assert output =~ "Dala Doctor"
      assert output =~ "Tools"
      assert output =~ "Project"
      assert output =~ "Build"
      assert output =~ "OTP Cache"
      assert output =~ "Devices"
      assert output =~ "Environment"
    end

    test "environment checks include port 4200 and version alignment" do
      output =
        capture_io(fn ->
          try do
            Mix.Tasks.Dala.Doctor.run([])
          rescue
            _ -> :ok
          end
        end)

      assert output =~ "Port 4200"
      assert output =~ "Version alignment"
    end
  end
end
