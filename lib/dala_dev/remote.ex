defmodule DalaDev.Remote do
  @moduledoc """
  Easy remote debugging and tracing interface for dala Elixir cluster nodes.

  Provides a simple interface to debug and trace remote nodes without needing
  to manually handle RPC calls or node selection.

  ## Usage

  ### Select a node

      iex> DalaDev.Remote.select_node(:"dala_demo@127.0.0.1")
      :ok

  ### List available nodes

      iex> DalaDev.Remote.nodes()
      [node1@host, node2@host]

  ### Call remote functions

      iex> DalaDev.Remote.Observer.observe()
      {:ok, %{system: %{...}, processes: [...], ...}}

      iex> DalaDev.Remote.Debugger.memory_report()
      {:ok, %{total: "1.2 GB", processes: "45 MB", ...}}

      iex> DalaDev.Remote.Debugger.inspect_process(MyApp.Worker)
      {:ok, %{pid: "#PID<0.123.0>", state: "...", ...}}

      iex> DalaDev.Remote.Debugger.eval("1 + 1")
      {:ok, 2}

      iex> DalaDev.Remote.Tracer.trace_messages(MyApp.Worker, duration: 5000)
      {:ok, [%{type: :send, message: "..."}, ...]}

  ### Set custom timeout

      iex> DalaDev.Remote.set_timeout(10_000)
      :ok

  ### Get current selection

      iex> DalaDev.Remote.selected_node()
      {:ok, node()}

  ## Automatic Node Selection

  If only one remote node is available, it will be automatically selected.
  If multiple nodes are available, you must explicitly select one.

  ## Default Timeout

  The default timeout for all remote operations is 5000ms (5 seconds).
  This can be changed using `set_timeout/1`.
  """

  use GenServer

  @default_timeout 5000

  # Client API

  @doc """
  Starts the Remote helper.

  This is automatically started by the application supervisor.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Lists all connected remote nodes (excluding the current node).
  """
  @spec nodes() :: [node()]
  def nodes do
    GenServer.call(__MODULE__, :nodes)
  end

  @doc """
  Selects a node for subsequent remote operations.

  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec select_node(node() | String.t()) :: :ok | {:error, term()}
  def select_node(node) when is_binary(node) do
    select_node(String.to_atom(node))
  end

  def select_node(node) when is_atom(node) do
    GenServer.call(__MODULE__, {:select_node, node})
  end

  @doc """
  Gets the currently selected node.

  Returns `{:ok, node}` if a node is selected, `{:error, :no_node_selected}` otherwise.
  """
  @spec selected_node() :: {:ok, node()} | {:error, :no_node_selected}
  def selected_node do
    GenServer.call(__MODULE__, :selected_node)
  end

  @doc """
  Sets the default timeout for remote operations.

  Returns `:ok`.
  """
  @spec set_timeout(non_neg_integer()) :: :ok
  def set_timeout(timeout) when is_integer(timeout) and timeout > 0 do
    GenServer.call(__MODULE__, {:set_timeout, timeout})
  end

  @doc """
  Gets the current timeout setting.

  Returns the timeout in milliseconds.
  """
  @spec get_timeout() :: non_neg_integer()
  def get_timeout do
    GenServer.call(__MODULE__, :get_timeout)
  end

  @doc """
  Clears the currently selected node.

  Returns `:ok`.
  """
  @spec clear_selection() :: :ok
  def clear_selection do
    GenServer.call(__MODULE__, :clear_selection)
  end

  @doc """
  Automatically selects a node if only one is available.

  Returns `{:ok, node}` if auto-selected, `{:error, reason}` otherwise.
  """
  @spec auto_select() :: {:ok, node()} | {:error, term()}
  def auto_select do
    GenServer.call(__MODULE__, :auto_select)
  end

  # Observer submodule

  defmodule Observer do
    @moduledoc """
    Remote observer functions for inspecting node state.

    These functions automatically use the node selected via
    `DalaDev.Remote.select_node/1`.
    """

    @doc """
    Observes a remote node and returns comprehensive system information.

    Returns `{:ok, data}` on success, `{:error, reason}` on failure.
    """
    @spec observe(keyword()) :: {:ok, map()} | {:error, term()}
    def observe(opts \\ []) do
      with {:ok, node} <- get_target_node(),
           timeout <- Keyword.get(opts, :timeout, DalaDev.Remote.get_timeout()) do
        DalaDev.Observer.observe(node, timeout: timeout)
      end
    end

    @doc """
    Gets system information from the selected node.
    """
    @spec system_info(keyword()) :: map()
    def system_info(opts \\ []) do
      with {:ok, node} <- get_target_node(),
           timeout <- Keyword.get(opts, :timeout, DalaDev.Remote.get_timeout()) do
        DalaDev.Observer.system_info(node, timeout)
      end
    end

    @doc """
    Gets the process list from the selected node.
    """
    @spec process_list(keyword()) :: [map()]
    def process_list(opts \\ []) do
      with {:ok, node} <- get_target_node(),
           timeout <- Keyword.get(opts, :timeout, DalaDev.Remote.get_timeout()) do
        DalaDev.Observer.process_list(node, timeout)
      end
    end

    @doc """
    Gets ETS tables from the selected node.
    """
    @spec ets_tables(keyword()) :: [map()]
    def ets_tables(opts \\ []) do
      with {:ok, node} <- get_target_node(),
           timeout <- Keyword.get(opts, :timeout, DalaDev.Remote.get_timeout()) do
        DalaDev.Observer.ets_tables(node, timeout)
      end
    end

    defp get_target_node do
      case DalaDev.Remote.selected_node() do
        {:ok, node} -> {:ok, node}
        {:error, _} = err -> err
      end
    end
  end

  # Debugger submodule

  defmodule Debugger do
    @moduledoc """
    Remote debugging functions for inspecting and controlling remote nodes.

    These functions automatically use the node selected via
    `DalaDev.Remote.select_node/1`.
    """

    @doc """
    Inspects a process on the selected node.

    The process can be specified as:
    - A PID (e.g., `#PID<0.123.0>`)
    - A registered name (atom)
    - A module name (atom)
    - A `{mod, fun}` tuple

    Returns `{:ok, info}` on success, `{:error, reason}` on failure.
    """
    @spec inspect_process(term(), keyword()) :: {:ok, map()} | {:error, term()}
    def inspect_process(process_ref, opts \\ []) do
      with {:ok, node} <- get_target_node(),
           timeout <- Keyword.get(opts, :timeout, DalaDev.Remote.get_timeout()) do
        if node == Node.self() do
          # Local execution - no RPC needed
          # Note: Can't inspect current process state due to :sys.get_state limitation
          pid = resolve_pid_local(process_ref)

          if pid == self() do
            {:error, :cannot_inspect_current_process}
          else
            case DalaDev.Debugger.inspect_process_local(process_ref) do
              {:ok, info} -> {:ok, info}
              {:error, _} = err -> err
            end
          end
        else
          DalaDev.Debugger.inspect_process(node, process_ref, timeout: timeout)
        end
      end
    end

    defp resolve_pid_local(process_ref) do
      case process_ref do
        pid when is_pid(pid) ->
          pid

        name when is_atom(name) ->
          case Process.whereis(name) do
            nil -> raise "Process not found: #{inspect(name)}"
            pid -> pid
          end

        {mod, fun} when is_atom(mod) and is_atom(fun) ->
          case Process.whereis(mod) do
            nil -> raise "Module not found: #{inspect(mod)}"
            pid -> pid
          end

        mod when is_atom(mod) ->
          case Process.whereis(mod) do
            nil -> raise "Module not found: #{inspect(mod)}"
            pid -> pid
          end
      end
    end

    @doc """
    Gets a memory report from the selected node.

    Returns `{:ok, report}` on success, `{:error, reason}` on failure.
    """
    @spec memory_report(keyword()) :: {:ok, map()} | {:error, term()}
    def memory_report(opts \\ []) do
      with {:ok, node} <- get_target_node(),
           timeout <- Keyword.get(opts, :timeout, DalaDev.Remote.get_timeout()) do
        if node == Node.self() do
          # Local execution - no RPC needed
          DalaDev.Debugger.memory_report_local()
        else
          DalaDev.Debugger.memory_report(node, timeout: timeout)
        end
      end
    end

    @doc """
    Gets the state of a process on the selected node.

    Similar to `:sys.get_state/1` from Erlang/OTP, this function retrieves
    the internal state of a process. The process must be a system process
    (e.g., a GenServer, GenStateMachine, or other process that implements
    the sys protocol).

    ## Parameters

    - `pid_or_name` - A PID or registered name of the process

    ## Returns

    - `{:ok, state}` on success, where `state` is the process state
    - `{:error, reason}` on failure

    ## Examples

        # Get state of a process by PID
        iex> DalaDev.Remote.Debugger.get_state(#PID<0.123.0>)
        {:ok, %{data: "...", status: :idle}}

        # Get state of a process by registered name
        iex> DalaDev.Remote.Debugger.get_state(:my_worker)
        {:ok, %{count: 42}}

    ## See Also

    - [Erlang sys:get_state/1](https://www.erlang.org/doc/apps/stdlib/sys.html#get_state/1)
    """
    @spec get_state(pid() | atom() | {atom(), atom()}, keyword()) ::
            {:ok, term()} | {:error, term()}
    def get_state(pid_or_name, opts \\ []) do
      with {:ok, node} <- get_target_node(),
           timeout <- Keyword.get(opts, :timeout, DalaDev.Remote.get_timeout()) do
        if node == Node.self() do
          # Local execution - no RPC needed
          case DalaDev.Debugger.get_process_state_local(pid_or_name) do
            nil -> {:error, :process_not_found}
            state -> {:ok, state}
          end
        else
          case :rpc.call(node, DalaDev.Debugger, :get_process_state, [pid_or_name], timeout) do
            nil -> {:error, :process_not_found}
            {:badrpc, reason} -> {:error, reason}
            state -> {:ok, state}
          end
        end
      end
    end

    @doc """
    Evaluates Elixir code on the selected node.

    Returns `{:ok, result}` on success, `{:error, reason}` on failure.

    ## Examples

        iex> DalaDev.Remote.Debugger.eval("1 + 1")
        {:ok, 2}

        iex> DalaDev.Remote.Debugger.eval("Enum.map(1..3, &(&1 * 2))")
        {:ok, [2, 4, 6]}

        iex> DalaDev.Remote.Debugger.eval("MyApp.Config.get(:api_key)")
        {:ok, "secret_key"}
    """
    @spec eval(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
    def eval(code, opts \\ []) do
      with {:ok, node} <- get_target_node(),
           timeout <- Keyword.get(opts, :timeout, DalaDev.Remote.get_timeout()),
           bindings <- Keyword.get(opts, :bindings, []) do
        if node == Node.self() do
          # Local execution - no RPC needed
          DalaDev.Debugger.eval_remote_local(code, bindings)
        else
          DalaDev.Debugger.eval_remote(node, code, timeout: timeout, bindings: bindings)
        end
      end
    end

    @doc """
    Traces messages sent to/from a process on the selected node.

    Returns `{:ok, messages}` on success, `{:error, reason}` on failure.

    ## Options

    - `:duration` - Tracing duration in ms (default: 5000)
    - `:timeout` - RPC timeout in ms (defaults to remote timeout)
    """
    @spec trace_messages(term(), keyword()) :: {:ok, [map()]} | {:error, term()}
    def trace_messages(process_ref, opts \\ []) do
      with {:ok, node} <- get_target_node(),
           duration <- Keyword.get(opts, :duration, 5000),
           timeout <- Keyword.get(opts, :timeout, DalaDev.Remote.get_timeout()) do
        if node == Node.self() do
          # Local execution - no RPC needed
          {:ok, DalaDev.Debugger.trace_messages_local(process_ref, duration)}
        else
          DalaDev.Debugger.trace_messages(node, process_ref, duration: duration, timeout: timeout)
        end
      end
    end

    @doc """
    Gets the supervision tree from the selected node.

    Returns `{:ok, tree}` on success, `{:error, reason}` on failure.
    """
    @spec supervision_tree(keyword()) :: {:ok, map()} | {:error, term()}
    def supervision_tree(opts \\ []) do
      with {:ok, node} <- get_target_node(),
           timeout <- Keyword.get(opts, :timeout, DalaDev.Remote.get_timeout()) do
        if node == Node.self() do
          # Local execution - no RPC needed
          DalaDev.Debugger.get_supervision_tree_local()
        else
          DalaDev.Debugger.get_supervision_tree(node, timeout: timeout)
        end
      end
    end

    defp get_target_node do
      case DalaDev.Remote.selected_node() do
        {:ok, node} -> {:ok, node}
        {:error, _} = err -> err
      end
    end
  end

  # LogCollector submodule

  defmodule LogCollector do
    @moduledoc """
    Remote log collection functions.

    These functions automatically use the node selected via
    `DalaDev.Remote.select_node/1`.
    """

    @doc """
    Collects logs from the selected node.

    Returns `{:ok, logs}` on success, `{:error, reason}` on failure.
    """
    @spec collect_logs(keyword()) :: {:ok, [map()]} | {:error, term()}
    def collect_logs(opts \\ []) do
      with {:ok, node} <- get_target_node() do
        DalaDev.LogCollector.collect_logs(node, opts)
      end
    end

    @doc """
    Collects Android logs from a device.

    Returns `{:ok, logs}` on success, `{:error, reason}` on failure.
    """
    @spec collect_android_logs(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
    def collect_android_logs(serial, opts \\ []) do
      DalaDev.LogCollector.collect_android_logs(serial, opts)
    end

    defp get_target_node do
      case DalaDev.Remote.selected_node() do
        {:ok, node} -> {:ok, node}
        {:error, _} = err -> err
      end
    end
  end

  # Rpc submodule

  defmodule Rpc do
    @moduledoc """
    Generic RPC call functions for executing arbitrary functions on remote nodes.

    These functions automatically use the node selected via
    `DalaDev.Remote.select_node/1`.

    ## Usage

        iex> DalaDev.Remote.Rpc.call(MyModule, :my_function, [arg1, arg2])
        {:ok, result}

        iex> DalaDev.Remote.Rpc.call(MyModule, :my_function, [arg1, arg2], timeout: 10_000)
        {:ok, result}
    """

    @doc """
    Calls a function on the selected remote node.

    ## Parameters

    - `module` - The module containing the function
    - `function` - The function name (atom)
    - `args` - List of arguments to pass to the function
    - `opts` - Options:
      - `:timeout` - RPC timeout in ms (defaults to remote timeout)

    ## Returns

    - `{:ok, result}` on success
    - `{:error, reason}` on failure

    ## Examples

        # Call a function with no arguments
        iex> DalaDev.Remote.Rpc.call(MyModule, :get_status, [])
        {:ok, :online}

        # Call a function with arguments
        iex> DalaDev.Remote.Rpc.call(MyModule, :add, [1, 2])
        {:ok, 3}

        # Call a function with custom timeout
        iex> DalaDev.Remote.Rpc.call(MyModule, :slow_function, [], timeout: 30_000)
        {:ok, result}
    """
    @spec call(module(), atom(), [term()], keyword()) :: {:ok, term()} | {:error, term()}
    def call(module, function, args, opts \\ []) do
      with {:ok, node} <- get_target_node(),
           timeout <- Keyword.get(opts, :timeout, DalaDev.Remote.get_timeout()) do
        if node == Node.self() do
          # Local execution - no RPC needed
          try do
            result = apply(module, function, args)
            {:ok, result}
          rescue
            e -> {:error, Exception.message(e)}
          end
        else
          :rpc.call(node, module, function, args, timeout)
        end
      end
    end

    defp get_target_node do
      case DalaDev.Remote.selected_node() do
        {:ok, node} -> {:ok, node}
        {:error, _} = err -> err
      end
    end
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %{
      selected_node: nil,
      timeout: @default_timeout
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:nodes, _from, state) do
    remote_nodes = Node.list()
    {:reply, remote_nodes, state}
  end

  @impl true
  def handle_call({:select_node, node}, _from, state) do
    if node in Node.list() or node == Node.self() do
      {:reply, :ok, %{state | selected_node: node}}
    else
      {:reply, {:error, :node_not_found}, state}
    end
  end

  @impl true
  def handle_call(:selected_node, _from, state) do
    case state.selected_node do
      nil -> {:reply, {:error, :no_node_selected}, state}
      node -> {:reply, {:ok, node}, state}
    end
  end

  @impl true
  def handle_call({:set_timeout, timeout}, _from, state) do
    {:reply, :ok, %{state | timeout: timeout}}
  end

  @impl true
  def handle_call(:get_timeout, _from, state) do
    {:reply, state.timeout, state}
  end

  @impl true
  def handle_call(:clear_selection, _from, state) do
    {:reply, :ok, %{state | selected_node: nil}}
  end

  @impl true
  def handle_call(:auto_select, _from, state) do
    case Node.list() do
      [] ->
        {:reply, {:error, :no_remote_nodes}, state}

      [single_node] ->
        {:reply, :ok, %{state | selected_node: single_node}}

      multiple_nodes ->
        {:reply,
         {:error,
          {:multiple_nodes, multiple_nodes,
           "Please select a node using DalaDev.Remote.select_node/1"}}, state}
    end
  end
end
