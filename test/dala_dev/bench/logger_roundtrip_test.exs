defmodule DalaDev.Bench.LoggerRoundTripTest do
  use ExUnit.Case, async: true

  alias DalaDev.Bench.{Logger, Probe}

  defp probe(opts \\ []) do
    %Probe{
      ts_ms: Keyword.get(opts, :ts_ms, 1_000),
      reachability: Keyword.get(opts, :reachability, :alive_rpc),
      app_process: Keyword.get(opts, :app_process, :app_running),
      usb: Keyword.get(opts, :usb, :usb_ok),
      screen: Keyword.get(opts, :screen, :on),
      battery_pct: Keyword.get(opts, :battery_pct, 80),
      reason: Keyword.get(opts, :reason)
    }
  end

  test "open/append/close writes a readable CSV" do
    path = Path.join(["test_tmp", "bench1_#{System.unique_integer()}", "bench_log.csv"])
    File.mkdir_p!(Path.dirname(path))
    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

    log = Logger.open(path, start_ts_ms: 0)
    assert log.rows == 0

    log = Logger.append(log, probe(ts_ms: 1_000))
    log = Logger.append(log, probe(ts_ms: 2_000, reason: "rpc timeout"))
    log = Logger.close(log)

    refute log.file
    assert log.rows == 2

    rows = Logger.read(path)
    assert length(rows) == 2

    [first, second] = rows
    assert first.battery_pct == 80
    assert first.screen == :on
    assert is_nil(first.reason)
    assert second.reason == "rpc timeout"
  end

  test "close/1 is idempotent" do
    path = Path.join(["test_tmp", "bench2_#{System.unique_integer()}", "bench_log2.csv"])
    File.mkdir_p!(Path.dirname(path))
    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

    log = Logger.open(path)
    log = Logger.close(log)
    assert %{file: nil} = Logger.close(log)
  end

  test "reason with special characters survives the round trip" do
    path = Path.join(["test_tmp", "bench3_#{System.unique_integer()}", "bench_log3.csv"])
    File.mkdir_p!(Path.dirname(path))
    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

    tricky = "comma, here\nnewline\ttab\\backslash"
    log = Logger.open(path, start_ts_ms: 0)
    Logger.append(log, probe(reason: tricky))
    Logger.close(log)

    [row] = Logger.read(path)
    assert row.reason == tricky
  end

  test "nil battery is preserved as nil" do
    path = Path.join(["test_tmp", "bench4_#{System.unique_integer()}", "bench_log4.csv"])
    File.mkdir_p!(Path.dirname(path))
    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

    log = Logger.open(path, start_ts_ms: 0)
    Logger.append(log, probe(battery_pct: nil))
    Logger.close(log)

    [row] = Logger.read(path)
    assert is_nil(row.battery_pct)
  end
end
