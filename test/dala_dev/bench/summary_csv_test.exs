defmodule DalaDev.Bench.SummaryCsvTest do
  use ExUnit.Case, async: true

  alias DalaDev.Bench.Summary

  @csv """
  ts_ms,elapsed_sec,reachability,app_process,usb,screen,battery_pct,reason
  1000,1.0,alive_rpc,app_running,usb_ok,on,80,
  2000,2.0,alive_rpc,app_running,usb_ok,off,79,
  3000,3.0,rpc_timeout,app_running,usb_ok,off,79,rpc timeout
  """

  describe "from_csv/1" do
    test "parses a CSV file into metrics" do
      path = Path.join(["test_tmp", "csv1_#{System.unique_integer()}", "bench.csv"])
      File.mkdir_p!(Path.dirname(path))
      on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)
      File.write!(path, @csv)

      m = Summary.from_csv(path)
      assert m.total_samples == 3
      assert m.successful_samples == 3
    end

    test "handles empty CSV" do
      path = Path.join(["test_tmp", "csv2_#{System.unique_integer()}", "bench_empty.csv"])
      File.mkdir_p!(Path.dirname(path))
      on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

      File.write!(
        path,
        "ts_ms,elapsed_sec,reachability,app_process,usb,screen,battery_pct,reason\n"
      )

      m = Summary.from_csv(path)
      assert m.total_samples == 0
    end
  end

  describe "pretty/1 output details" do
    test "includes drain percentage when battery data present" do
      rows = [
        %{
          ts_ms: 0,
          elapsed_sec: 0.0,
          reachability: :alive_rpc,
          app_process: :app_running,
          usb: :usb_ok,
          screen: :on,
          battery_pct: 100,
          reason: nil
        },
        %{
          ts_ms: 60_000,
          elapsed_sec: 60.0,
          reachability: :alive_rpc,
          app_process: :app_running,
          usb: :usb_ok,
          screen: :on,
          battery_pct: 90,
          reason: nil
        }
      ]

      output = Summary.pretty(Summary.from_rows(rows))
      assert output =~ "10"
    end
  end
end
