defmodule DalaDev.ClusterViz do
  @moduledoc """
  Cluster visualization for dala Elixir nodes.

  Provides web-based dashboard with D3.js graphs for:
  - Cluster topology visualization
  - Node health dashboard
  - Process distribution visualization
  - LiveView message flow diagram
  - Real-time metrics (memory, reductions, message queue)

  Integrates with `dala.server` to serve the dashboard.
  """

  alias DalaDev.Benchmark

  @type node_info :: %{
          node: node(),
          status: :alive | :unreachable,
          memory: map(),
          reductions: integer(),
          process_count: integer(),
          message_queue_len: integer(),
          latency_ms: integer() | nil
        }

  @doc """
  Generate cluster topology data.

  Returns a map with:
  - `:nodes` - List of node information
  - `:connections` - List of {node1, node2} tuples
  - `:timestamp` - Current timestamp
  """
  @spec topology() :: {:ok, map()} | {:error, term()}
  def topology() do
    nodes = Node.list(:connected) ++ [Node.self()]

    node_infos =
      Enum.map(nodes, fn node ->
        info = get_node_info(node)
        Map.put(info, :node, node)
      end)

    connections = generate_connections(nodes)

    {:ok,
     %{
       nodes: node_infos,
       connections: connections,
       timestamp: DateTime.utc_now()
     }}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Generate node health dashboard data.

  Returns a map with per-node metrics.
  """
  @spec health_dashboard() :: {:ok, map()} | {:error, term()}
  def health_dashboard() do
    nodes = Node.list(:connected) ++ [Node.self()]

    node_data =
      Enum.map(nodes, fn node ->
        # Get memory info;
        # Benchmark.memory_profile/2 returns a bare snapshot list (or a badrpc).
        memory_info =
          case Benchmark.memory_profile(node, duration: 1000, interval: 500) do
            snapshots when is_list(snapshots) -> compute_memory_stats(snapshots)
            _ -> %{error: "Memory profile failed"}
          end

        # Get latency;
        latency =
          case DalaDev.NetworkDiag.ping_node(node) do
            {:ok, ms} -> ms
            {:error, _} -> nil
          end

        %{
          node: node,
          status: if(node in Node.list(), do: :alive, else: :unreachable),
          memory: memory_info,
          latency_ms: latency,
          process_count: length(Process.list())
        }
      end)

    {:ok,
     %{
       nodes: node_data,
       timestamp: DateTime.utc_now()
     }}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Generate process distribution visualization data.

  Returns a map with:
  - `:supervisors` - Supervision tree structure
  - `:processes` - Process list with stats
  """
  @spec process_distribution() :: {:ok, map()} | {:error, term()}
  def process_distribution() do
    nodes = Node.list(:connected) ++ [Node.self()]

    all_data =
      Enum.flat_map(nodes, fn node ->
        case DalaDev.Debugger.get_supervision_tree(node, []) do
          {:ok, tree} ->
            [%{node: node, tree: tree}]

          {:error, _} ->
            []
        end
      end)

    {:ok,
     %{
       nodes: all_data,
       timestamp: DateTime.utc_now()
     }}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Generate LiveView message flow data.

  Returns a map with message flow between processes.
  """
  @spec liveview_flow() :: {:ok, map()} | {:error, term()}
  def liveview_flow() do
    # Placeholder - would trace LiveView message flows;
    {:ok,
     %{
       flows: [],
       timestamp: DateTime.utc_now()
     }}
  end

  @doc """
  Generate HTML dashboard page.

  Options:
  - `:port` - Server port (default: 4000)
  - `:refresh_interval` - Auto-refresh interval in ms (default: 5000)
  """
  @spec generate_dashboard(keyword()) :: {:ok, :started} | {:error, term()}
  def generate_dashboard(opts \\ []) do
    port = Keyword.get(opts, :port, 4000)
    refresh = Keyword.get(opts, :refresh_interval, 5000)

    # Start a simple HTTP server;
    Task.start(fn ->
      apply(:cowboy, :start_clear, [port, dispatch: dispatch_rules(refresh)])
    end)

    DalaDev.Output.info("Dashboard available at: http://localhost:#{port}/dashboard")
    {:ok, :started}
  end

  # ── Private helpers ──────────────────────────────;

  defp get_node_info(node) do
    case Benchmark.memory_profile(node, duration: 1000, interval: 500) do
      snapshots when is_list(snapshots) ->
        %{
          memory: compute_memory_stats(snapshots),
          process_count: length(Process.list())
        }

      _ ->
        %{error: "Failed to get node info"}
    end
  end

  defp compute_memory_stats(snapshots) when is_list(snapshots) do
    total_memory =
      Enum.map(snapshots, & &1.memory) |> Enum.sum()

    avg_memory = div(total_memory, length(snapshots))

    %{
      total_memory: total_memory,
      avg_memory: avg_memory,
      sample_count: length(snapshots)
    }
  end

  defp generate_connections(nodes) do
    # Simple: all connected nodes are connected to each other;
    Enum.flat_map(nodes, fn node1 ->
      Enum.map(nodes, fn node2 ->
        if node1 != node2 and node2 in Node.list() do
          {node1, node2}
        else
          nil
        end
      end)
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp dispatch_rules(refresh) do
    [
      {:_, [], DalaDev.Server.ClusterVizHandler, %{refresh_interval: refresh}}
    ]
  end
end
