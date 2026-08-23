defmodule DalaDev.UtilsTest do
  use ExUnit.Case, async: true

  describe "compile_regex/2" do
    test "compiles valid regex" do
      assert %Regex{} = DalaDev.Utils.compile_regex("hello\\s+world")
    end

    test "raises on invalid regex" do
      assert_raise RuntimeError, ~r/invalid regex pattern/i, fn ->
        DalaDev.Utils.compile_regex("[invalid")
      end
    end

    test "accepts options" do
      regex = DalaDev.Utils.compile_regex("hello", "i")
      assert Regex.match?(regex, "HELLO")
    end
  end

  describe "command_available?/1" do
    test "returns true for available command" do
      # ls should always be available on Unix
      assert DalaDev.Utils.command_available?("ls") == true
    end

    test "returns false for unavailable command" do
      assert DalaDev.Utils.command_available?("nonexistent_command_12345") == false
    end
  end

  describe "format_bytes/1" do
    test "formats bytes" do
      assert DalaDev.Utils.format_bytes(500) == "500 B"
    end

    test "formats kilobytes" do
      assert DalaDev.Utils.format_bytes(2048) == "2.0 KB"
    end

    test "formats megabytes" do
      # 2MB to be clear of boundary
      assert DalaDev.Utils.format_bytes(2_097_152) == "2.0 MB"
    end

    test "formats gigabytes" do
      # 2GB to be clear of boundary
      assert DalaDev.Utils.format_bytes(2_147_483_648) == "2.0 GB"
    end
  end

  describe "ensure_dir/1" do
    test "creates directory if not exists" do
      path = Path.join(System.tmp_dir!(), "dala_test_#{:erlang.unique_integer([:positive])}")
      assert :ok = DalaDev.Utils.ensure_dir(path)
      assert File.dir?(path)
      File.rm_rf!(path)
    end

    test "returns :ok if directory already exists" do
      path = System.tmp_dir!()
      assert :ok = DalaDev.Utils.ensure_dir(path)
    end
  end

  describe "parse_adb_devices_output/1" do
    test "parses serials from tab-separated output" do
      output = """
      List of devices attached
      emulator-5554\tdevice product:sdk_gphone64_arm64
      R5CW3089HVB\tdevice usb:1234
      """

      assert DalaDev.Utils.parse_adb_devices_output(output) == [
               "emulator-5554",
               "R5CW3089HVB"
             ]
    end

    test "skips blank lines" do
      output = "List of devices attached\n\nemulator-5554\tdevice\n"

      assert DalaDev.Utils.parse_adb_devices_output(output) == ["emulator-5554"]
    end

    test "returns empty list for header only" do
      assert DalaDev.Utils.parse_adb_devices_output("List of devices attached\n") == []
    end
  end

  describe "run_adb_for_device/3" do
    test "prepends -s serial to args and returns error for missing adb target" do
      if DalaDev.Utils.adb_available?() do
        # A bogus serial fails cleanly rather than crashing.
        assert match?(
                 {:error, _},
                 DalaDev.Utils.run_adb_for_device("no-such-serial-xyz", ["get-state"],
                   timeout: 5000
                 )
               )
      else
        assert function_exported?(DalaDev.Utils, :run_adb_for_device, 3)
      end
    end
  end

  describe "adb_available?/0" do
    test "returns true only when adb is on PATH" do
      expected = System.find_executable("adb") != nil
      assert DalaDev.Utils.adb_available?() == expected
    end
  end

  describe "run_adb_with_timeout/2" do
    test "returns ok with trimmed output on success" do
      assert {:ok, "hello"} =
               DalaDev.Utils.run_adb_with_timeout(["x"],
                 exec: fn _args, _opts -> {"hello\n", 0} end
               )
    end

    test "returns error with output on non-zero exit" do
      assert {:error, "boom"} =
               DalaDev.Utils.run_adb_with_timeout(["x"],
                 exec: fn _args, _opts -> {"boom\n", 1} end
               )
    end

    test "returns {:error, :timeout} and does not hang past the timeout" do
      start = System.monotonic_time(:millisecond)

      assert {:error, :timeout} =
               DalaDev.Utils.run_adb_with_timeout(["x"],
                 timeout: 50,
                 exec: fn _args, _opts ->
                   Process.sleep(10_000)
                   {"late", 0}
                 end
               )

      elapsed = System.monotonic_time(:millisecond) - start
      assert elapsed < 5_000
    end

    test "passes args verbatim to the executor (no shell joining)" do
      parent = self()

      DalaDev.Utils.run_adb_with_timeout(["shell", "echo", "a b"],
        exec: fn args, _opts ->
          send(parent, {:args, args})
          {"ok", 0}
        end
      )

      assert_received {:args, ["shell", "echo", "a b"]}
    end

    test "forwards stderr_to_stdout option to the executor" do
      parent = self()

      DalaDev.Utils.run_adb_with_timeout(["x"],
        stderr_to_stdout: false,
        exec: fn _args, opts ->
          send(parent, {:opts, opts})
          {"ok", 0}
        end
      )

      assert_received {:opts, [stderr_to_stdout: false]}
    end
  end

  describe "normalize_cli_args/1" do
    test "rewrites underscored long flags to hyphenated form" do
      assert DalaDev.Utils.normalize_cli_args(["--on_conflict", "skip"]) ==
               ["--on-conflict", "skip"]

      assert DalaDev.Utils.normalize_cli_args(["--dry_run"]) == ["--dry-run"]

      assert DalaDev.Utils.normalize_cli_args(["--no_keep_alive", "--no-csv"]) ==
               ["--no-keep-alive", "--no-csv"]
    end

    test "handles --flag=value form" do
      assert DalaDev.Utils.normalize_cli_args(["--log_path=/tmp/x"]) == ["--log-path=/tmp/x"]
    end

    test "leaves values, short flags, and bare -- untouched" do
      args = ["local.txt", "/remote/path_with_underscore", "-x"]

      assert DalaDev.Utils.normalize_cli_args(args) ==
               ["local.txt", "/remote/path_with_underscore", "-x"]

      assert DalaDev.Utils.normalize_cli_args([]) == []
      assert DalaDev.Utils.normalize_cli_args(["--"]) == ["--"]
    end

    test "normalizes flags after positional values" do
      assert DalaDev.Utils.normalize_cli_args(["a.txt", "/r/a.txt", "--on_conflict", "skip"]) ==
               ["a.txt", "/r/a.txt", "--on-conflict", "skip"]
    end
  end
end
