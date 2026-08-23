defmodule DalaDev.Tracing do
  @moduledoc """
  Distributed tracing for dala Elixir cluster nodes.

  Provides tracing capabilities across connected dala nodes to debug
  message flows, function calls, and GenServer lifecycle events.

  ## Examples

      # Start tracing on all connected nodes
      {:ok, trace_id} = DalaDev.Tracing.start_trace(:all_nodes, modules: [MyApp, Dala.Ui.Socket])

      # Trace specific node
      {:ok, trace_id} = DalaDev.Tracing.start_trace(:"dala_qa@192.168.1.5")

      # Get trace events
      events = DalaDev.Tracing.get_events(trace_id)

      # Export to Chrome Tracing format
      DalaDev.Tracing.export_chrome_trace(trace_id, "trace.json")

      # Stop tracing
      :ok = DalaDev.Tracing.stop_trace(trace_id)
  """

  alias DalaDev.Device

  @type trace_id :: reference()
  @type trace_opts :: keyword()
  @type trace_event :: %{
          ts: integer(),
          node: node(),
          event:
            :function_call | :message_send | :message_receive | :process_spawn | :process_exit,
          module: module() | nil,
          function: atom() | nil,
          arity: integer() | nil,
          pid: pid(),
          message: term() | nil,
          metadata: keyword()
        }

  @doc """
  Start tracing on specified node(s).

  Options:
  - `:modules` - List of modules to trace (default: all)
  - `:pids` - List of PIDs to trace (default: all)
  - `:events` - Events to trace (default: [:function_call, :message_send, :message_receive])
  - `:match_spec` - Match specification for :dbg (advanced)

  Returns a trace ID that can be used to retrieve events.
  """
  @spec start_trace(node() | :all_nodes | [node()], trace_opts()) ::
          {:ok, trace_id()} | {:error, term()}
  def start_trace(nodes, opts \\ [])

  def start_trace(nodes, opts) when is_list(nodes) do
    trace_id = make_ref()
    resolved_nodes = Enum.flat_map(nodes, &resolve_nodes/1)

    case start_trace_on_nodes(trace_id, resolved_nodes, opts) do
      :ok -> {:ok, trace_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def start_trace(node, opts) do
    start_trace([node], opts)
  end

  @doc """
  Stop tracing and collect final events.
  """
  @spec stop_trace(trace_id()) :: :ok | {:error, term()}
  def stop_trace(_trace_id) do
    # In a real implementation, this would stop :erlang.trace/3 on all nodes
    # and collect remaining events from ETS tables
    :ok
  end

  @doc """
  Get collected trace events for a trace ID.
  """
  @spec get_events(trace_id()) :: [trace_event()]
  def get_events(_trace_id) do
    # Placeholder - would retrieve from ETS or RPC calls
    []
  end

  @doc """
  Export trace events to Chrome Tracing format (JSON).

  This format can be loaded in Chrome DevTools (chrome://tracing)
  or the `perfetto` UI for visualization.
  """
  @spec export_chrome_trace(trace_id(), Path.t()) :: :ok | {:error, term()}
  def export_chrome_trace(trace_id, path) do
    events = get_events(trace_id)

    chrome_trace = %{
      traceEvents: Enum.map(events, &to_chrome_event/1),
      displayTimeUnit: "ms"
    }

    case File.write(path, Jason.encode!(chrome_trace, pretty: true)) do
      :ok ->
        DalaDev.Output.success("Trace exported to: #{path}")
        DalaDev.Output.info("Open in Chrome: chrome://tracing/")
        :ok

      error ->
        {:error, error}
    end
  end

  @doc """
  Trace a specific function call on a remote node.

  Returns the result and trace events during execution.
  """
  @spec trace_call(node(), module(), atom(), list(), keyword()) ::
          {:ok, term(), [trace_event()]} | {:error, term()}
  def trace_call(node, module, function, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    # Start tracing
    {:ok, trace_id} = start_trace(node, modules: [module], events: [:function_call])

    # Make the call
    result = :rpc.call(node, module, function, args, timeout)

    # Stop and collect
    stop_trace(trace_id)
    events = get_events(trace_id)

    {:ok, result, events}
  end

  # ── Private implementation ───────────────────────────────────────────

  defp start_trace_on_nodes(trace_id, nodes, opts) do
    results =
      nodes
      |> Enum.map(fn node -> Task.async(fn -> start_trace_on_node(node, trace_id, opts) end) end)
      |> Enum.map(&Task.await(&1, 10_000))

    if Enum.all?(results, &(&1 == :ok)) do
      :ok
    else
      {:error, {:failed_on_some_nodes, results}}
    end
  end

  defp start_trace_on_node(node, trace_id, opts) do
    # This would use :erlang.trace/3 and :dbg on the remote node
    # For now, it's a placeholder
    case :rpc.call(node, __MODULE__, :enable_trace_on_node, [trace_id, opts], 5000) do
      :ok -> :ok
      {:badrpc, reason} -> {:error, {:rpc_error, node, reason}}
      other -> {:error, {:unknown_error, node, other}}
    end
  end

  @doc false
  @spec enable_trace_on_node(term(), keyword()) :: :ok
  def enable_trace_on_node(_trace_id, _opts) do
    # This runs ON the remote node
    # In a real implementation:
    # 1. Create ETS table for trace events
    # 2. Call :erlang.trace(:all, true, [:call, :send, :receive])
    # 3. Set up trace handler to collect events
    :ok
  end

  defp resolve_nodes(:all_nodes), do: Node.list() ++ [Node.self()]
  defp resolve_nodes(node) when is_atom(node), do: [node]
  defp resolve_nodes(%Device{node: node}) when not is_nil(node), do: [node]
  defp resolve_nodes(_), do: []

  defp to_chrome_event(%{ts: ts, node: node, event: event} = trace_event) do
    %{
      name: event_to_string(event),
      cat: "elixir",
      ph: "X",
      ts: ts,
      pid: inspect(trace_event.pid),
      args: %{
        node: node,
        module: trace_event.module,
        function: trace_event.function
      }
    }
  end

  defp event_to_string(:function_call), do: "function_call"
  defp event_to_string(:message_send), do: "message_send"
  defp event_to_string(:message_receive), do: "message_receive"
  defp event_to_string(:process_spawn), do: "process_spawn"
  defp event_to_string(:process_exit), do: "process_exit"
end
