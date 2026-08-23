defmodule DalaDev.BenchmarkReportTest do
  use ExUnit.Case, async: false

  alias DalaDev.Benchmark

  @results [
    %{
      name: "op_a",
      node: :a@x,
      wall_time: 1_500,
      reductions: 100,
      memory: 1_024,
      process_count: 3,
      message_queue_len: 0
    },
    %{
      name: "op_b",
      node: :a@x,
      wall_time: 2_500,
      reductions: 200,
      memory: 2_048,
      process_count: 4,
      message_queue_len: 1
    }
  ]

  describe "report/2" do
    test "generates a text report by default" do
      assert {:ok, text} = Benchmark.report(@results)
      assert text =~ "Wall Time"
      # Exact tab-separated row for op_a: node, wall time, reductions, memory,
      # processes, message queue length.
      assert text =~ "a@x\t1500\t100\t1024\t3\t0"
    end

    test "generates an html report" do
      assert {:ok, html} = Benchmark.report(@results, format: :html)
      assert html =~ "<"
    end

    test "generates json report" do
      assert {:ok, json} = Benchmark.report(@results, format: :json)
      assert {:ok, decoded} = JSON.decode(json)
      assert length(decoded) == 2
    end

    test "writes to file when :output given" do
      path = Path.join("test_tmp", "bench_report.txt")
      File.mkdir_p!(Path.dirname(path))
      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, :ok} = Benchmark.report(@results, output: path)
      assert File.exists?(path)
    end

    test "returns error for unwritable output" do
      assert {:error, _} = Benchmark.report(@results, output: "/nonexistent/x.txt")
    end
  end

  describe "run_and_measure/1" do
    test "measures a local fun" do
      local = Node.self()

      assert {:ok, _result, %{node: ^local, wall_time: wall_time, reductions: reductions} = stats} =
               Benchmark.run_and_measure(fn -> Enum.map(1..10, &(&1 * 2)) end)

      assert is_integer(wall_time) and wall_time >= 0
      assert reductions >= 0
      assert Map.has_key?(stats, :memory)
    end
  end

  describe "measure/3" do
    test "measures on the local node" do
      assert {:ok, :ok_result, _stats} =
               Benchmark.measure(Node.self(), fn -> :ok_result end, timeout: 5_000)
    end
  end

  describe "memory_profile/2" do
    test "returns snapshot list for the local node" do
      snapshots = Benchmark.memory_profile(Node.self(), duration: 150, interval: 50)
      assert [snap | _] = snapshots
      assert length(snapshots) >= 1

      assert is_integer(snap.memory) and snap.memory > 0
      assert %DateTime{} = snap.ts
    end
  end
end
