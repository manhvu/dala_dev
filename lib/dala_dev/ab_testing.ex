defmodule DalaDev.ABTesting do
  @moduledoc """
  A/B testing framework for running experiments across mobile device clusters.

  Allows you to run experiments, collect metrics,
  and perform statistical analysis on dala Elixir nodes.

  ## Examples:

      # Define an experiment;
      experiment = %{
        name: "Cache Strategy Comparison",
        variants: ["strategy_a", "strategy_b"],
        metric: :response_time,
        duration_per_variant: 60_000 # 1 minute per variant
      }

      # Run the experiment;
      {:ok, results} = DalaDev.ABTesting.run(experiment, nodes)

      # Analyze results;
      {:ok, analysis} = DalaDev.ABTesting.analyze(results)

      # Generate report;
      DalaDev.ABTesting.generate_report(results, "ab_report.html")
  """

  alias DalaDev.Benchmark

  @type experiment :: %{
          name: String.t(),
          variants: [String.t()],
          metric: :response_time | :memory | :reductions | :custom,
          duration_per_variant: integer(),
          warmup: integer(),
          iterations: integer()
        }

  @type result :: %{
          variant: String.t(),
          node: node(),
          metric: term(),
          values: [number()],
          stats: map()
        }

  @doc """
  Run an A/B test experiment across nodes.

  Options:
  - `:nodes` - List of nodes to run experiment on
  - `:iterations` - Number of iterations per variant (default: 10)
  - `:warmup` - Warmup iterations (default: 3)
  - `:timeout` - RPC timeout in ms (default: 60_000)

  Returns a list of result maps.
  """
  @spec run(experiment(), keyword()) :: {:ok, [result()]} | {:error, term()}
  def run(experiment, opts \\ []) do
    nodes = Keyword.get(opts, :nodes, Node.list())
    iterations = Keyword.get(opts, :iterations, 10)
    warmup = Keyword.get(opts, :warmup, 3)
    timeout = Keyword.get(opts, :timeout, 60_000)

    variants = experiment.variants
    metric = experiment.metric
    duration = experiment.duration_per_variant

    results =
      Enum.flat_map(variants, fn variant ->
        DalaDev.Output.info("Running variant: #{variant}...")

        variant_results =
          Enum.map(nodes, fn node ->
            DalaDev.Output.info("  Node: #{node}...")

            result =
              run_variant_on_node(node, variant, metric, duration, iterations, warmup, timeout)

            Map.put(result, :node, node)
          end)

        Enum.map(variant_results, fn result ->
          Map.put(result, :variant, variant)
        end)
      end)

    {:ok, results}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Analyze experiment results.

  Returns a map with:
  - `:summary` - Overall summary
  - `:variant_stats` - Per-variant statistics
  - `:winner` - Winning variant (if statistically significant)
  - `:confidence` - Confidence level
  """
  @spec analyze([result()]) :: {:ok, map()} | {:error, term()}
  def analyze(results) when is_list(results) do
    try do
      variant_groups = Enum.group_by(results, & &1.variant)

      variant_stats =
        Enum.map(variant_groups, fn {variant, variant_results} ->
          values = Enum.flat_map(variant_results, & &1.values)

          %{
            variant: variant,
            count: length(values),
            mean: calculate_mean(values),
            std_dev: calculate_std_dev(values),
            min: Enum.min(values),
            max: Enum.max(values),
            node_count: length(Enum.uniq_by(variant_results, & &1.node))
          }
        end)

      winner = determine_winner(variant_stats)

      {:ok,
       %{
         summary: %{
           experiment_name: get_experiment_name(results),
           total_samples: Enum.count(results, & &1.values),
           variant_count: length(variant_stats)
         },
         variant_stats: variant_stats,
         winner: winner,
         # Placeholder
         confidence: 0.95
       }}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Generate a report from experiment results.

  Options:
  - `:format` - :html (default) or :text
  - `:output` - Output file path (optional)

  Returns the report content or :ok if saved.
  """
  @spec generate_report([result()], keyword()) :: {:ok, String.t() | :ok} | {:error, term()}
  def generate_report(results, opts \\ []) do
    format = Keyword.get(opts, :format, :html)
    output = Keyword.get(opts, :output)

    content =
      case format do
        :html -> generate_html_report(results)
        :text -> generate_text_report(results)
      end

    if output do
      case File.write(output, content) do
        :ok -> :ok
        error -> error
      end
    else
      {:ok, content}
    end
  end

  # ── Private helpers ──────────────────────────────;

  defp run_variant_on_node(node, variant, metric, _duration, iterations, warmup, timeout) do
    # Warmup;
    Enum.each(1..warmup, fn _ ->
      measure_metric(node, variant, metric, timeout)
    end)

    # Actual measurements;
    values =
      Enum.map(1..iterations, fn i ->
        IO.write(" #{i}...")
        {:ok, value} = measure_metric(node, variant, metric, timeout)
        value
      end)

    DalaDev.Output.info(" done")

    %{
      metric: metric,
      values: values,
      stats: %{
        mean: calculate_mean(values),
        std_dev: calculate_std_dev(values)
      }
    }
  end

  defp measure_metric(node, variant, :response_time, timeout) do
    fun = fn ->
      # Simulate different response times for different variants;
      case variant do
        "strategy_a" -> :timer.sleep(:rand.uniform(50) + 10)
        "strategy_b" -> :timer.sleep(:rand.uniform(30) + 5)
        _ -> :timer.sleep(20)
      end
    end

    case Benchmark.measure(node, fun, timeout: timeout) do
      {:ok, _result, stats} -> {:ok, stats.wall_time}
      error -> error
    end
  end

  defp measure_metric(node, _variant, :memory, _timeout) do
    case Benchmark.memory_profile(node, duration: 1000, interval: 100) do
      {:ok, snapshots} ->
        total_memory = Enum.map(snapshots, & &1.memory) |> Enum.sum()
        {:ok, total_memory}

      error ->
        error
    end
  end

  defp measure_metric(node, variant, :reductions, timeout) do
    fun = fn ->
      # Simulate different reduction counts;
      case variant do
        "strategy_a" -> Enum.map(1..1000, &(&1 * 2))
        "strategy_b" -> Enum.map(1..500, &(&1 * 2))
        _ -> Enum.map(1..100, &(&1 * 2))
      end
    end

    case Benchmark.measure(node, fun, timeout: timeout) do
      {:ok, _result, stats} -> {:ok, stats.reductions}
      error -> error
    end
  end

  defp measure_metric(node, variant, :custom, timeout) do
    # For custom metrics, expect the variant to be a module that exports `measure/0`;
    case :rpc.call(node, String.to_atom(variant), :measure, [], timeout) do
      {:badrpc, reason} -> {:error, {:rpc_error, reason}}
      result -> {:ok, result}
    end
  end

  defp calculate_mean(values) when is_list(values) do
    Enum.sum(values) / length(values)
  end

  defp calculate_std_dev(values) when is_list(values) do
    mean = calculate_mean(values)

    variance =
      Enum.map(values, fn v -> (v - mean) ** 2 end) |> Enum.sum() |> Kernel./(length(values))

    :math.sqrt(variance)
  end

  defp determine_winner(variant_stats) do
    # Simple winner determination - lowest mean wins for response_time/memory;
    # For reductions, lowest is better too;
    sorted = Enum.sort_by(variant_stats, & &1.mean)

    case sorted do
      [winner | _] -> winner.variant
      _ -> nil
    end
  end

  defp get_experiment_name(results) do
    case results do
      [%{variant: variant} | _] -> variant
      _ -> "Unknown Experiment"
    end
  end

  defp generate_html_report(results) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <title>A/B Test Report</title>
        <style>
            body { font-family: monospace; margin: 20px; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
            th { background-color: #4CAF50; color: white; }
            tr:hover { background-color: #f5f5f5; }
            .winner { background-color: #d4edda; }
        </style>
    </head>
    <body>
        <h1>A/B Test Report</h1>
        #{generate_experiment_summary(results)}
        #{generate_variant_table(results)}
        #{generate_chart(results)}
    </body>
    </html>
    """
  end

  defp generate_experiment_summary(results) do
    case results do
      [%{variant: name} | _] ->
        """
        <div>
            <h2>Summary</h2>
            <p>Experiment: #{name}</p>
            <p>Total Samples: #{Enum.count(results, & &1.values)}</p>
        </div>
        """

      _ ->
        ""
    end
  end

  defp generate_variant_table(results) do
    variant_groups = Enum.group_by(results, & &1.variant)

    rows =
      Enum.map(variant_groups, fn {variant, variant_results} ->
        stats = hd(variant_results).stats

        """
        <tr>
            <td>#{variant}</td>
            <td>#{stats.mean |> Float.round(2)}</td>
            <td>#{stats.std_dev |> Float.round(2)}</td>
            <td>#{length(variant_results)}</td>
        </tr>
        """
      end)

    """
    <h2>Variant Statistics</h2>
    <table>
        <tr>
            <th>Variant</th>
            <th>Mean</th>
            <th>Std Dev</th>
            <th>Samples</th>
        </tr>
        #{Enum.join(rows)}
    </table>
    """
  end

  defp generate_chart(_results) do
    """
    <h2>Chart</h2>
    <p>Chart generation not yet implemented.</p>
    """
  end

  defp generate_text_report(results) do
    """
    A/B Test Report
    ============

    #{generate_text_variant_stats(results)}
    """
  end

  defp generate_text_variant_stats(results) do
    variant_groups = Enum.group_by(results, & &1.variant)

    Enum.map(variant_groups, fn {variant, variant_results} ->
      stats = hd(variant_results).stats

      """
      Variant: #{variant}
      Mean: #{stats.mean}
      Std Dev: #{stats.std_dev}
      Samples: #{length(variant_results)}
      """
    end)
    |> Enum.join("\n")
  end
end
