defmodule DalaDev.OutputTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias DalaDev.Output

  setup do
    Output.configure(quiet: false, json: false)
    :ok
  end

  describe "configure/1" do
    test "quiet mode suppresses info and success but not errors" do
      Output.configure(quiet: true)

      assert capture_io(:stdio, fn ->
               Output.info("hidden")
               Output.success("hidden")
               Output.error("visible")
             end) =~ "visible"

      refute capture_io(:stdio, fn -> Output.step("Deploying") end) =~ "Deploying"
    end

    test "json flag is queryable" do
      refute Output.json?()
      Output.configure(json: true)
      assert Output.json?()
    end
  end

  describe "emit helpers" do
    test "success prints a check" do
      output = capture_io(:stdio, fn -> Output.success("pushed 42 BEAMs") end)
      assert output =~ "✓"
      assert output =~ "pushed 42 BEAMs"
    end

    test "warn prints a marker" do
      output = capture_io(:stdio, fn -> Output.warn("stale cache") end)
      assert output =~ "stale cache"
    end

    test "error prints a marker" do
      output = capture_io(:stdio, fn -> Output.error("adb not found") end)
      assert output =~ "adb not found"
    end

    test "hint prints an arrow" do
      output = capture_io(:stdio, fn -> Output.hint("Run mix dala.doctor") end)
      assert output =~ "Run mix dala.doctor"
    end

    test "step prints a header" do
      output = capture_io(:stdio, fn -> Output.step("Deploying", "to devices") end)
      assert output =~ "==>"
      assert output =~ "Deploying to devices"
    end
  end

  describe "timed/2" do
    test "returns the fun result and prints elapsed time" do
      output =
        capture_io(:stdio, fn ->
          send(self(), Output.timed("Compiling", fn -> :ok end))
        end)

      assert_received :ok
      assert output =~ ~r/Compiling \(\d+(\.\d+)?(µs|ms|s)\)/
    end

    test "re-raises on failure after printing failure line" do
      output =
        capture_io(:stdio, fn ->
          try do
            Output.timed("Building", fn -> raise "boom" end)
          rescue
            _ -> :caught
          end
        end)

      assert output =~ "failed"
      assert output =~ "Building"
    end
  end

  describe "format_elapsed/1" do
    test "formats microseconds" do
      assert Output.format_elapsed(500) == "500µs"
    end

    test "formats milliseconds" do
      assert Output.format_elapsed(1_500) == "1.5ms"
    end

    test "formats seconds" do
      assert Output.format_elapsed(1_500_000) == "1.5s"
    end

    test "formats minutes" do
      assert Output.format_elapsed(125_000_000) == "2m5s"
    end
  end

  describe "format_bytes/1" do
    test "formats byte sizes" do
      assert Output.format_bytes(500) == "500 B"
      assert Output.format_bytes(2_048) == "2.0 KB"
      assert Output.format_bytes(5 * 1_048_576) == "5.0 MB"
      assert Output.format_bytes(2 * 1_073_741_824) == "2.0 GB"
    end
  end
end
