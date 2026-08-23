defmodule DalaDev.CrashDumpTest do
  use ExUnit.Case, async: true

  alias DalaDev.CrashDump

  @sample_dump """
  Crash dump created on: 2026-08-22T10:00:00
  OTP release: 27
  Elixir version: 1.18.2
  Node name: dala_demo_ios@127.0.0.1
  Compile time: 2026-08-01T00:00:00
  Error in process: <0.200.0>
  Error reason: badarg
  Memory total: 1048576
  Memory processes: 524288
  Memory system: 262144
  """

  describe "parse/1" do
    test "parses a full crash dump" do
      assert {:ok, info} = CrashDump.parse(@sample_dump)

      assert info.header.created_at == "2026-08-22T10:00:00"
      assert info.system_info.otp_release == "27"
      assert info.system_info.elixir_version == "1.18.2"
      assert info.system_info.node == "dala_demo_ios@127.0.0.1"
      assert info.error_info.type == "<0.200.0>"
      assert info.error_info.reason == "badarg"
      assert info.memory.total == "1048576"
      assert info.memory.processes == "524288"
      assert info.memory.system == "262144"
      assert info.summary == "Crash dump parsed: 2026-08-22T10:00:00"
    end

    test "handles empty content" do
      assert {:ok, info} = CrashDump.parse("")
      assert info.error_info == nil
      assert info.process_info == []
      assert info.ets_tables == []
    end

    test "error info absent when no error lines" do
      content = "OTP release: 27\n"
      assert {:ok, info} = CrashDump.parse(content)
      assert info.error_info == nil
    end
  end

  describe "parse_file/1" do
    test "reads and parses a file" do
      path = Path.join("test_tmp", "crash_dump_test.dump")
      File.mkdir_p!(Path.dirname(path))
      on_exit(fn -> File.rm_rf!(path) end)
      File.write!(path, @sample_dump)

      assert {:ok, info} = CrashDump.parse_file(path)
      assert info.memory.total == "1048576"

      File.rm(path)
    end

    test "returns error for missing file" do
      assert {:error, :enoent} = CrashDump.parse_file("/nonexistent/crash.dump")
    end
  end

  describe "summary/1" do
    test "generates a readable summary" do
      {:ok, info} = CrashDump.parse(@sample_dump)
      summary = CrashDump.summary(info)

      assert summary =~ "BEAM Crash Dump Summary"
      assert summary =~ "27"
      assert summary =~ "badarg"
      assert summary =~ "ETS Tables: 0"
    end

    test "summary without error info" do
      {:ok, info} = CrashDump.parse("")
      summary = CrashDump.summary(info)
      assert summary =~ "No error information found."
    end
  end

  describe "html_report/1" do
    test "generates an HTML report" do
      {:ok, info} = CrashDump.parse(@sample_dump)
      html = CrashDump.html_report(info)

      assert html =~ "<!DOCTYPE html>"
      assert html =~ "BEAM Crash Dump Report"
      assert html =~ "badarg"
      assert html =~ "1048576"
    end

    test "html report with no error info" do
      {:ok, info} = CrashDump.parse("")
      html = CrashDump.html_report(info)
      assert html =~ "No error information"
    end
  end
end
