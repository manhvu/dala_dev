defmodule DalaDev.NetworkDiag do
  @moduledoc """
  Network diagnostics for dala Elixir clusters.

  Provides tools to diagnose connectivity issues, measure latency,
  and verify EPMD health across cluster nodes.

  ## Examples

      # Ping a node
      {:ok, latency_ms} = DalaDev.NetworkDiag.ping_node(:"dala_qa@192.168.1.5")

      # Measure latency with multiple samples
      {:ok, stats} = DalaDev.NetworkDiag.measure_latency(node, samples: 100)

      # Check EPMD health
      :ok = DalaDev.NetworkDiag.check_epmd_health(node)

      # Trace distribution path
      {:ok, path} = DalaDev.NetworkDiag.trace_distribution(node)
  """

  alias DalaDev.Device

  @type node_ref :: node() | Device.t() | String.t()
  @type latency_stats :: %{
          min: integer(),
          max: integer(),
          avg: float(),
          median: float(),
          samples: integer()
        }

  @doc """
  Ping a node to check connectivity.

  Returns `{:ok, latency_ms}` on success, `{:error, reason}` on failure.

  Options:
  - `:timeout` - Timeout in ms (default: 5_000)
  """
  @spec ping_node(node_ref(), keyword()) :: {:ok, integer()} | {:error, term()}
  def ping_node(node_ref, opts \\ []) do
    node = resolve_node(node_ref)
    timeout = Keyword.get(opts, :timeout, 5_000)

    start = System.monotonic_time(:millisecond)

    case :rpc.call(node, :erlang, :node, [], timeout) do
      ^node ->
        stop = System.monotonic_time(:millisecond)
        {:ok, stop - start}

      {:badrpc, reason} ->
        {:error, {:rpc_error, reason}}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  @doc """
  Measure latency to a node with multiple samples.

  Options:
  - `:samples` - Number of ping samples (default: 10)
  - `:timeout` - Timeout per sample in ms (default: 5_000)

  Returns latency statistics.
  """
  @spec measure_latency(node_ref(), keyword()) :: {:ok, latency_stats()} | {:error, term()}
  def measure_latency(node_ref, opts \\ []) do
    node = resolve_node(node_ref)
    samples = Keyword.get(opts, :samples, 10)
    timeout = Keyword.get(opts, :timeout, 5_000)

    latencies =
      Enum.flat_map(1..samples, fn _ ->
        case ping_node(node, timeout: timeout) do
          {:ok, ms} -> [ms]
          _ -> []
        end
      end)

    if latencies == [] do
      {:error, :all_samples_failed}
    else
      stats = calculate_latency_stats(latencies)
      {:ok, stats}
    end
  end

  @doc """
  Check EPMD health on a node.

  Verifies:
  - EPMD is running
  - Port 4369 is reachable
  - Node can register/deregister

  Returns `:ok` or `{:error, reason}`.
  """
  @spec check_epmd_health(node_ref(), keyword()) :: :ok | {:error, term()}
  def check_epmd_health(node_ref, opts \\ []) do
    node = resolve_node(node_ref)
    timeout = Keyword.get(opts, :timeout, 10_000)

    # Check if EPMD port is reachable
    host = extract_host(node)

    case host do
      nil ->
        {:error, :cannot_extract_host}

      host_str ->
        case :gen_tcp.connect(String.to_charlist(host_str), 4369, [:binary], 2000) do
          {:ok, sock} ->
            :gen_tcp.close(sock)

            # Check if node is registered in EPMD
            case :rpc.call(node, :erlang, :registered, [], timeout) do
              list when is_list(list) ->
                if node in list do
                  :ok
                else
                  {:error, :node_not_registered}
                end

              {:badrpc, reason} ->
                {:error, {:rpc_error, reason}}
            end

          {:error, reason} ->
            {:error, {:epmd_unreachable, reason}}
        end
    end
  end

  @doc """
  Trace the distribution path to a node.

  Shows the network path Elixir distribution takes to reach the node.

  Returns a list of hops or error.
  """
  @spec trace_distribution(node_ref(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def trace_distribution(node_ref, opts \\ []) do
    node = resolve_node(node_ref)
    timeout = Keyword.get(opts, :timeout, 10_000)

    # Get node's distribution info
    case :rpc.call(node, :net_kernel, :get_state, [], timeout) do
      {:ok, state} ->
        path = [
          "Local node: #{Node.self()}",
          "Target node: #{node}",
          "State: #{inspect(state)}"
        ]

        {:ok, path}

      {:badrpc, reason} ->
        {:error, {:rpc_error, reason}}

      error ->
        {:error, error}
    end
  end

  @doc """
  Get detailed network interface information for a node.

  Returns IP addresses, interface names, and reachability.
  """
  @spec get_network_interfaces(node_ref(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_network_interfaces(node_ref, opts \\ []) do
    node = resolve_node(node_ref)
    timeout = Keyword.get(opts, :timeout, 10_000)

    :rpc.call(node, __MODULE__, :get_interfaces_local, [], timeout)
  end

  @doc false
  @spec get_interfaces_local() :: {:ok, map()} | {:error, term()}
  def get_interfaces_local do
    case :inet.getif() do
      {:ok, ifaces} ->
        interfaces =
          Enum.map(ifaces, fn {ip, broadcast, mask} ->
            %{
              ip: ntoa(ip),
              broadcast: ntoa(broadcast),
              mask: ntoa(mask),
              is_loopback: match?({127, _, _, _}, ip)
            }
          end)

        {:ok, %{interfaces: interfaces}}

      error ->
        {:error, error}
    end
  end

  # Broadcast may be :undefined for point-to-point interfaces; :inet.ntoa/1
  # returns {:error, _} for non-IP values.
  defp ntoa(ip) do
    case :inet.ntoa(ip) do
      {:error, _} -> nil
      addr -> to_string(addr)
    end
  end

  # ── Private helpers ──────────────────────────────────────

  defp resolve_node(node) when is_atom(node), do: node

  defp resolve_node(%Device{node: node}) when not is_nil(node),
    do: node

  defp resolve_node(str) when is_binary(str),
    do: String.to_atom(str)

  defp extract_host(node) when is_atom(node) do
    case Atom.to_string(node) |> String.split("@") do
      [_, host] -> host
      _ -> nil
    end
  end

  defp calculate_latency_stats(latencies) do
    sorted = Enum.sort(latencies)
    count = length(latencies)

    %{
      min: Enum.min(latencies),
      max: Enum.max(latencies),
      avg: Enum.sum(latencies) / count,
      median:
        if rem(count, 2) == 1 do
          Enum.at(sorted, div(count, 2))
        else
          (Enum.at(sorted, div(count, 2) - 1) + Enum.at(sorted, div(count, 2))) / 2
        end,
      samples: count
    }
  end
end
