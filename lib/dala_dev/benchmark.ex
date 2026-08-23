defmodule DalaDev.Benchmark do
  @moduledoc """
  Runtime benchmarking for dala Elixir nodes.

  Measure execution time, memory usage, reductions, and compare
  performance across different devices in the cluster.

  ## Examples

      # Measure a function on a remote node
      {:ok, result, stats} = DalaDev.Benchmark.measure(
        :"dala_qa@192.168.1.5",
        fn -> MyApp.heavy_computation() end
      )

      # Compare performance across nodes
      DalaDev.Benchmark.compare([node1, node2], test_module: MyBench)

      # Profile memory usage
      DalaDev.Benchmark.memory_profile(node, duration: 60_000)
  """

  alias DalaDev.Device

  @type node_ref :: node() | Device.t() | :all_nodes
  @type benchmark_result :: %{
          node: node(),
          wall_time: integer(),
          reductions: integer(),
          memory: integer(),
          process_count: integer(),
          message_queue_len: integer()
        }

  @doc """
  Measure execution time and resource usage of a function on a remote node.

  Options:
  - `:timeout` - RPC timeout in ms (default: 30_000)
  - `:warmup` - Number of warmup iterations (default: 1)
  - `:iterations` - Number of measurement iterations (default: 1)

  Returns `{:ok, result, stats}` or `{:error, reason}`.
  """
  @spec measure(node_ref(), (-> any()), keyword()) ::
          {:ok, any(), benchmark_result()} | {:error, term()}
  def measure(node_ref, fun, opts \\ []) when is_function(fun, 0) do
    node = resolve_node(node_ref)
    timeout = Keyword.get(opts, :timeout, 30_000)
    warmup = Keyword.get(opts, :warmup, 1)
    iterations = Keyword.get(opts, :iterations, 1)

    # Warmup
    Enum.each(1..warmup, fn _ -> :rpc.call(node, __MODULE__, :run_and_measure, [fun], timeout) end)

    # Measure
    results =
      Enum.map(1..iterations, fn _ ->
        :rpc.call(node, __MODULE__, :run_and_measure, [fun], timeout)
      end)

    case results do
      [{:error, reason} | _] ->
        {:error, reason}

      measurements when is_list(measurements) ->
        # Use first successful measurement
        {:ok, result, stats} = hd(Enum.filter(measurements, &match?({:ok, _, _}, &1)))
        {:ok, result, stats}

      other ->
        {:error, {:unexpected_result, other}}
    end
  end

  @doc """
  Compare performance across multiple nodes.

  Options:
  - `:test_module` - Module containing benchmark functions
  - `:test_function` - Function to call (default: :run/0)
  - `:iterations` - Number of iterations per node

  Returns a list of benchmark results for comparison.
  """
  @spec compare([node_ref()], keyword()) :: [benchmark_result()]
  def compare(nodes, opts \\ []) do
    test_module = Keyword.get(opts, :test_module)
    test_function = Keyword.get(opts, :test_function, :run)
    iterations = Keyword.get(opts, :iterations, 3)

    Enum.map(nodes, fn node_ref ->
      node = resolve_node(node_ref)

      case measure(node, fn -> :rpc.call(node, test_module, test_function, []) end,
             iterations: iterations
           ) do
        {:ok, _, stats} -> stats
        _ -> %{node: node, error: :benchmark_failed}
      end
    end)
  end

  @doc """
  Profile memory usage on a node over time.

  Options:
  - `:duration` - Profile duration in ms (default: 60_000)
  - `:interval` - Sampling interval in ms (default: 1_000)

  Returns memory statistics over time.
  """
  @spec memory_profile(node_ref(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def memory_profile(node_ref, opts \\ []) do
    node = resolve_node(node_ref)
    duration = Keyword.get(opts, :duration, 60_000)
    interval = Keyword.get(opts, :interval, 1_000)

    :rpc.call(node, __MODULE__, :profile_memory_locally, [duration, interval], duration + 5_000)
  end

  @doc """
  Generate a benchmark report.

  Options:
  - `:format` - :text (default), :html, or :json
  - `:output` - Output file path (optional)

  Returns the report content or :ok if saved to file.
  """
  @spec report([benchmark_result()], keyword()) :: {:ok, String.t() | :ok} | {:error, term()}
  def report(results, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    output = Keyword.get(opts, :output)

    content =
      case format do
        :text -> generate_text_report(results)
        :html -> generate_html_report(results)
        :json -> JSON.encode!(results)
      end

    if output do
      case File.write(output, content) do
        :ok -> {:ok, :ok}
        error -> error
      end
    else
      {:ok, content}
    end
  end

  @doc false
  @spec run_and_measure((-> any())) :: {:ok, any(), map()}
  def run_and_measure(fun) when is_function(fun, 0) do
    # Get initial stats
    initial_stats = get_process_stats(self())

    {wall_time, result} = :timer.tc(fun)

    final_stats = get_process_stats(self())

    stats = %{
      node: node(),
      wall_time: wall_time,
      reductions: final_stats.reductions - initial_stats.reductions,
      memory: final_stats.memory,
      process_count: final_stats.process_count,
      message_queue_len: final_stats.message_queue_len
    }

    {:ok, result, stats}
  end

  @doc false
  @spec profile_memory_locally(non_neg_integer(), non_neg_integer()) :: [map()]
  def profile_memory_locally(duration, interval) do
    end_time = System.monotonic_time(:millisecond) + duration

    Stream.unfold(nil, fn _ ->
      if System.monotonic_time(:millisecond) < end_time do
        snapshot = %{
          ts: DateTime.utc_now(),
          memory: :erlang.memory(:total),
          process_count: length(Process.list()),
          reductions: :erlang.statistics(:reductions)
        }

        Process.sleep(interval)
        {snapshot, nil}
      else
        nil
      end
    end)
    |> Enum.to_list()
  end

  # ── Private helpers ──────────────────────────────────────────────

  defp resolve_node(node) when is_atom(node), do: node

  defp resolve_node(%Device{node: node}) when not is_nil(node),
    do: node

  defp resolve_node(:all_nodes),
    do: Node.self()

  defp get_process_stats(pid) do
    info =
      Process.info(pid, [:reductions, :memory, :message_queue_len])
      |> Keyword.merge(Process.info(pid, [:links, :monitors]) || [])

    %{
      reductions: Keyword.get(info, :reductions, 0),
      memory: Keyword.get(info, :memory, 0),
      message_queue_len: Keyword.get(info, :message_queue_len, 0),
      process_count: length(Process.list())
    }
  end

  defp generate_text_report(results) do
    header = "Node\tWall Time (μs)\tReductions\tMemory (bytes)\tProcesses\tMsgQ"

    rows =
      Enum.map(results, fn r ->
        "#{r.node}\t#{r.wall_time}\t#{r.reductions}\t#{r.memory}\t#{r.process_count}\t#{r.message_queue_len}"
      end)

    Enum.join([header | rows], "\n")
  end

  defp generate_html_report(results) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Benchmark Report</title>
        <style>
            body { font-family: monospace; margin: 20px; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
            th { background-color: #4CAF50; color: white; }
            tr:nth-child(even) { background-color: #f2f2f2; }
        </style>
    </head>
    <body>
        <h1>Benchmark Report</h1>
        <table>
            <tr>
                <th>Node</th>
                <th>Wall Time (μs)</th>
                <th>Reductions</th>
                <th>Memory (bytes)</th>
                <th>Processes</th>
                <th>Msg Queue</th>
            </tr>
    """
    |> then(fn html ->
      Enum.reduce(results, html, fn r, acc ->
        acc <>
          """
          <tr>
              <td>#{r.node}</td>
              <td>#{r.wall_time}</td>
              <td>#{r.reductions}</td>
              <td>#{r.memory}</td>
              <td>#{r.process_count}</td>
              <td>#{r.message_queue_len}</td>
          </tr>
          """
      end)
    end)
    |> then(fn html ->
      html <>
        """
        </table>
        <p>Generated: #{DateTime.utc_now()}</p>
        </body>
        </html>
        """
    end)
  end
end
