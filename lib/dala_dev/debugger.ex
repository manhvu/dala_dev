defmodule DalaDev.Debugger do
  @moduledoc """
  Advanced debugging tools for remote Elixir nodes.

  Provides process inspection, state introspection, remote code evaluation,
  and memory analysis for dala Elixir cluster debugging.

  ## Examples

      # Inspect a process on a remote node
      {:ok, info} = DalaDev.Debugger.inspect_process(
        :"dala_qa@192.168.1.5",
        MyApp.Worker
      )

      # Get supervision tree
      {:ok, tree} = DalaDev.Debugger.get_supervision_tree(node)

      # Evaluate code on remote node
      {:ok, result} = DalaDev.Debugger.eval_remote(
        node,
        "MyApp.Config.get(:api_key)"
      )

      # Get memory report
      {:ok, report} = DalaDev.Debugger.memory_report(node)
  """

  alias DalaDev.Device

  @type node_ref :: node() | Device.t() | String.t()
  @type process_ref :: pid() | atom() | {atom(), atom()} | module()

  @doc """
  Inspect a process on a remote node.

  Returns detailed information including:
  - Process dictionary
  - Current state (if GenServer/GenStateMachine)
  - Message queue
  - Links and monitors
  - Memory usage

  Options:
  - `:timeout` - RPC timeout in ms (default: 10_000)
  """
  @spec inspect_process(node_ref(), process_ref(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def inspect_process(node_ref, process_ref, opts \\ []) do
    node = resolve_node(node_ref)
    timeout = Keyword.get(opts, :timeout, 10_000)

    :rpc.call(node, __MODULE__, :inspect_process_local, [process_ref], timeout)
  end

  @doc """
  Get the supervision tree of a node.

  Returns a tree structure showing all supervisors and their children.
  """
  @spec get_supervision_tree(node_ref(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_supervision_tree(node_ref, opts) do
    node = resolve_node(node_ref)
    timeout = Keyword.get(opts, :timeout, 15_000)

    :rpc.call(node, __MODULE__, :get_supervision_tree_local, [], timeout)
  end

  @spec get_supervision_tree(node_ref()) :: {:ok, map()} | {:error, term()}
  def get_supervision_tree(node_ref) do
    get_supervision_tree(node_ref, [])
  end

  @doc """
  Evaluate Elixir code on a remote node.

  The code string is evaluated using `Code.eval_string/1` on the remote node.

  Options:
  - `:timeout` - RPC timeout in ms (default: 30_000)
  - `:bindings` - Variables to bind in the evaluation context
  """
  @spec eval_remote(node_ref(), String.t(), keyword()) ::
          {:ok, any()} | {:error, term()}
  def eval_remote(node_ref, code, opts \\ []) do
    node = resolve_node(node_ref)
    timeout = Keyword.get(opts, :timeout, 30_000)
    bindings = Keyword.get(opts, :bindings, [])

    :rpc.call(node, __MODULE__, :eval_remote_local, [code, bindings], timeout)
  end

  @doc """
  Get a detailed memory report for a node.

  Returns memory breakdown including:
  - Total memory
  - Process memory
  - Binary memory
  - ETS memory
  - Atom memory
  """
  @spec memory_report(node_ref(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def memory_report(node_ref, opts \\ []) do
    node = resolve_node(node_ref)
    timeout = Keyword.get(opts, :timeout, 10_000)

    :rpc.call(node, __MODULE__, :memory_report_local, [], timeout)
  end

  @doc """
  Trace messages sent to/from a process.

  Options:
  - `:duration` - Tracing duration in ms (default: 5_000)
  - `:timeout` - RPC timeout in ms (default: duration + 1_000)
  """
  @spec trace_messages(node_ref(), process_ref(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def trace_messages(node_ref, process_ref, opts \\ []) do
    node = resolve_node(node_ref)
    duration = Keyword.get(opts, :duration, 5_000)
    timeout = Keyword.get(opts, :timeout, duration + 1_000)

    :rpc.call(node, __MODULE__, :trace_messages_local, [process_ref, duration], timeout)
  end

  @doc false
  @spec inspect_process_local(process_ref()) :: {:ok, map()} | {:error, term()}
  def inspect_process_local(process_ref) do
    pid = resolve_pid(process_ref)

    case Process.info(pid, [
           :dictionary,
           :message_queue_len,
           :memory,
           :reductions,
           :links,
           :monitors,
           :group_leader,
           :status,
           :current_function,
           :current_location
         ]) do
      info when is_list(info) ->
        info_map = Map.new(info)

        # Try to get GenServer/GenStateMachine state
        state = get_process_state(pid)

        %{
          pid: inspect(pid),
          dictionary: format_dict(Map.get(info_map, :dictionary, [])),
          message_queue_len: Map.get(info_map, :message_queue_len, 0),
          memory: Map.get(info_map, :memory, 0),
          reductions: Map.get(info_map, :reductions, 0),
          links: Map.get(info_map, :links, []),
          monitors: Map.get(info_map, :monitors, []),
          status: Map.get(info_map, :status, :unknown),
          current_function: format_mfa(Map.get(info_map, :current_function)),
          current_location: Map.get(info_map, :current_location),
          state: state
        }
        |> then(fn result -> {:ok, result} end)

      nil ->
        {:error, :process_not_found}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc false
  @spec get_supervision_tree_local() :: {:ok, map()} | {:error, term()}
  def get_supervision_tree_local do
    case Process.whereis(:supervisor) do
      nil ->
        # Try to get all supervisors
        supervisors =
          Process.list()
          |> Enum.filter(fn pid ->
            info = Process.info(pid, [:dictionary])
            dict = Keyword.get(info || [], :dictionary, [])
            Keyword.get(dict, :"$initial_call") |> is_supervisor?()
          end)

        %{
          supervisors: Enum.map(supervisors, &inspect/1),
          note: "Basic supervisor detection (no :supervisor process found)"
        }
        |> then(fn result -> {:ok, result} end)

      sup_pid ->
        tree = build_supervision_tree(sup_pid)
        {:ok, tree}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc false
  @spec eval_remote_local(String.t(), list()) :: {:ok, any()} | {:error, term()}
  def eval_remote_local(code, bindings) do
    try do
      {result, _bindings} = Code.eval_string(code, bindings)
      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc false
  @spec memory_report_local() :: {:ok, map()}
  def memory_report_local do
    mem = :erlang.memory()

    report = %{
      node: node(),
      total: format_bytes(Keyword.get(mem, :total, 0)),
      processes: format_bytes(Keyword.get(mem, :processes_used, 0)),
      system: format_bytes(Keyword.get(mem, :system, 0)),
      atom: format_bytes(Keyword.get(mem, :atom_used, 0)),
      binary: format_bytes(Keyword.get(mem, :binary, 0)),
      code: format_bytes(Keyword.get(mem, :code, 0)),
      ets: format_bytes(Keyword.get(mem, :ets, 0)),
      raw: mem
    }

    {:ok, report}
  end

  @doc """
  Gets the state of a process.

  Similar to `:sys.get_state/1` from Erlang/OTP, this function retrieves
  the internal state of a process. The process must be a system process
  (e.g., a GenServer, GenStateMachine, or other process that implements
  the sys protocol).

  ## Parameters

  - `pid_or_name` - A PID or registered name of the process

  ## Returns

  - The process state, or `nil` if the process is not found or doesn't have state

  ## See Also

  - [Erlang sys:get_state/1](https://www.erlang.org/doc/apps/stdlib/sys.html#get_state/1)
  """
  @spec get_process_state_local(pid() | atom() | {atom(), atom()}) :: term() | nil
  def get_process_state_local(pid_or_name) do
    pid = resolve_pid_safe(pid_or_name)
    get_process_state(pid)
  end

  defp resolve_pid_safe(pid) when is_pid(pid), do: pid

  defp resolve_pid_safe(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> nil
      pid -> pid
    end
  end

  defp resolve_pid_safe({mod, fun}) when is_atom(mod) and is_atom(fun) do
    case Process.whereis(mod) do
      nil -> nil
      pid -> pid
    end
  end

  defp resolve_pid_safe(mod) when is_atom(mod) do
    case Process.whereis(mod) do
      nil -> nil
      pid -> pid
    end
  end

  @doc false
  @spec trace_messages_local(process_ref(), non_neg_integer()) :: {:ok, [map()]}
  def trace_messages_local(process_ref, duration) do
    pid = resolve_pid(process_ref)

    # Check if process is alive
    if Process.alive?(pid) do
      # Set up tracing
      :erlang.trace(pid, true, [:send, :receive, :timestamp])

      # Collect messages for duration
      messages =
        collect_trace_messages(duration, pid, [])
        |> Enum.reverse()

      # Stop tracing
      :erlang.trace(pid, false, [:send, :receive])

      {:ok, messages}
    else
      {:ok, []}
    end
  end

  # ── Private helpers ─────────────────────────────────────────

  defp resolve_node(node) when is_atom(node), do: node

  defp resolve_node(%Device{node: node}) when not is_nil(node),
    do: node

  defp resolve_node(str) when is_binary(str) do
    String.to_atom(str)
  end

  defp resolve_pid(pid) when is_pid(pid), do: pid

  defp resolve_pid(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> raise "Process not found: #{inspect(name)}"
      pid -> pid
    end
  end

  defp resolve_pid({mod, fun}) when is_atom(mod) and is_atom(fun) do
    case Process.whereis(mod) do
      nil -> raise "Module not found: #{inspect(mod)}"
      pid -> pid
    end
  end

  defp resolve_pid(mod) when is_atom(mod) do
    case Process.whereis(mod) do
      nil -> raise "Module not found: #{inspect(mod)}"
      pid -> pid
    end
  end

  defp get_process_state(pid) do
    # Try to get state from GenServer or GenStateMachine
    try do
      # This is a best-effort attempt
      case :sys.get_state(pid) do
        state when not is_nil(state) -> inspect(state)
        _ -> nil
      end
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
  end

  defp is_supervisor?({:supervisor, _mod, _arity}), do: true
  defp is_supervisor?(_), do: false

  defp build_supervision_tree(sup_pid) do
    # Simplified - in reality would use :supervisor.get_childspecs/1
    %{
      pid: inspect(sup_pid),
      children: []
    }
  end

  defp collect_trace_messages(0, _pid, acc), do: acc

  defp collect_trace_messages(time_left, pid, acc) do
    receive do
      {:trace, ^pid, :send, msg, to} ->
        collect_trace_messages(
          time_left - 1,
          pid,
          [%{type: :send, message: inspect(msg), to: inspect(to)} | acc]
        )

      {:trace, ^pid, :receive, msg} ->
        collect_trace_messages(
          time_left - 1,
          pid,
          [%{type: :receive, message: inspect(msg)} | acc]
        )
    after
      100 ->
        acc
    end
  end

  defp format_dict(dict) when is_list(dict) do
    Enum.map(dict, fn {k, v} -> "#{inspect(k)}: #{inspect(v)}" end)
  end

  defp format_mfa({mod, fun, arity}), do: "#{inspect(mod)}.#{fun}/#{arity}"
  defp format_mfa(other), do: inspect(other)

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"

  defp format_bytes(bytes) when bytes < 1024 * 1024,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_bytes(bytes),
    do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
end
