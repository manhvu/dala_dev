defmodule Mix.Tasks.Dala.CacheTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1" do
    test "read-only listing works without crashing" do
      output = capture_io(fn -> Mix.Tasks.Dala.Cache.run([]) end)
      assert output =~ "Dala caches on this machine"
      assert output =~ "read-only"
    end

    test "dry-run mode prints without deleting" do
      output = capture_io(fn -> Mix.Tasks.Dala.Cache.run(["--clear", "--dry-run"]) end)
      assert output =~ "dry-run"
    end
  end
end
