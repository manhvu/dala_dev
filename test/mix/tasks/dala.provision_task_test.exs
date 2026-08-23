defmodule Mix.Tasks.Dala.ProvisionTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1 — environment guards" do
    test "raises when no ios/ directory present" do
      # The test env (dala_dev repo root) has no ios/ dir
      assert catch_error(
               capture_io(fn ->
                 Mix.Tasks.Dala.Provision.run([])
               end)
             )
    end
  end
end
