defmodule Mix.Tasks.Dala.Bench do
  use Mix.Task

  @shortdoc "Run benchmarks on dala nodes"

  @moduledoc """
  Run performance benchmarks on dala Elixir nodes.

  ## Examples

      # Run standard benchmarks
      mix dala.bench

      # Run custom benchmark script
      mix dala.bench --test test/my_bench.exs

      # Compare performance across nodes
      mix dala.bench --compare node1@host,node2@host

      # Generate HTML report
      mix dala.bench --report report.html --format html

  ## Options

    * `--test` - Path to custom benchmark script
    * `--compare` - Comma-separated list of nodes to compare
    * `--report` - Output file for report
    * `--format` - Report format (text, html, json)
    * `--iterations` - Number of iterations per benchmark (default: 3)
  """

  alias DalaDev.Benchmark

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])

    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          test: :string,
          compare: :string,
          report: :string,
          format: :string,
          iterations: :integer
        ],
        aliases: [
          t: :test,
          c: :compare,
          r: :report,
          f: :format,
          i: :iterations
        ]
      )

    cond do
      Keyword.has_key?(opts, :compare) ->
        run_comparison(opts)

      Keyword.has_key?(opts, :test) ->
        run_custom_benchmark(opts)

      true ->
        run_standard_benchmark(opts)
    end
  end

  defp run_standard_benchmark(opts) do
    iterations = Keyword.get(opts, :iterations, 3)
    format = Keyword.get(opts, :format, "text")
    report_path = Keyword.get(opts, :report)

    DalaDev.Output.step("Running standard benchmarks")
    DalaDev.Output.info("Iterations: #{iterations}")

    # Benchmark: List operations
    DalaDev.Output.step("Benchmarking", "list operations")

    result1 =
      Benchmark.measure(
        Node.self(),
        fn ->
          Enum.map(1..1000, &(&1 * 2))
        end,
        iterations: iterations
      )

    case result1 do
      {:ok, _, stats} ->
        print_benchmark_result("List mapping (1000 items)", stats)

      {:error, reason} ->
        DalaDev.Output.error("Benchmark failed: #{inspect(reason)}")
    end

    # Benchmark: String operations
    DalaDev.Output.step("Benchmarking", "string operations")

    result2 =
      Benchmark.measure(
        Node.self(),
        fn ->
          String.duplicate("a", 1000)
        end,
        iterations: iterations
      )

    case result2 do
      {:ok, _, stats} ->
        print_benchmark_result("String duplicate (1000 chars)", stats)

      {:error, reason} ->
        DalaDev.Output.error("Benchmark failed: #{inspect(reason)}")
    end

    # Generate report if requested
    if report_path do
      results = collect_results([result1, result2])
      generate_report(results, format, report_path)
    end
  end

  defp run_comparison(opts) do
    nodes_str = Keyword.get(opts, :compare, "")
    iterations = Keyword.get(opts, :iterations, 3)

    nodes =
      nodes_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.to_atom/1)

    DalaDev.Output.info("Comparing performance across nodes: #{inspect(nodes)}")

    # Define a simple benchmark module
    benchmark_fn = fn ->
      Enum.map(1..1000, &(&1 * 2))
    end

    results =
      Enum.map(nodes, fn node ->
        DalaDev.Output.step("Benchmarking", node)

        case Benchmark.measure(node, benchmark_fn, iterations: iterations) do
          {:ok, _, stats} ->
            print_benchmark_result("Node: #{node}", stats)
            stats

          {:error, reason} ->
            DalaDev.Output.error("Failed on #{node}: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    # Generate report if requested
    if Keyword.has_key?(opts, :report) do
      generate_report(results, "text", Keyword.get(opts, :report))
    end
  end

  defp run_custom_benchmark(opts) do
    test_path = Keyword.get(opts, :test)

    if File.exists?(test_path) do
      DalaDev.Output.info("Running custom benchmark: #{test_path}")

      try do
        Code.eval_file(test_path)
      rescue
        e -> DalaDev.Output.error("Failed to run benchmark: #{Exception.message(e)}")
      end
    else
      DalaDev.Output.error("Benchmark file not found: #{test_path}")
    end
  end

  defp print_benchmark_result(name, stats) do
    DalaDev.Output.info("""
    #{name}:
      Wall time: #{stats.wall_time} μs
      Reductions: #{stats.reductions}
      Memory: #{format_bytes(stats.memory)}
      Process count: #{stats.process_count}
      Message queue: #{stats.message_queue_len}
    """)
  end

  defp collect_results(results) do
    Enum.flat_map(results, fn
      {:ok, _, stats} -> [stats]
      _ -> []
    end)
  end

  defp generate_report(results, format, path) do
    format_atom = String.to_atom(format)

    case Benchmark.report(results, format: format_atom, output: path) do
      {:ok, :ok} ->
        DalaDev.Output.success("Report saved to: #{path}")

      {:error, reason} ->
        DalaDev.Output.error("Failed to generate report: #{inspect(reason)}")
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"

  defp format_bytes(bytes) when bytes < 1024 * 1024,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes),
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
end
