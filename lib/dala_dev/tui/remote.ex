defmodule DalaDev.Tui.Remote do
  @moduledoc """
  Remote node information for the TUI.

  Queries connected dala nodes for version info, screen state,
  memory usage, process info, and debugging data.
  """

  defstruct [
    :node,
    :version,
    :otp_version,
    :erts_version,
    :app_version,
    :current_screen,
    :screen_info,
    :assigns,
    :memory,
    :process_count,
    :supervision_tree,
    :latency_ms,
    :connected_at,
    :error
  ]

  @type t :: %__MODULE__{
          node: atom(),
          version: String.t() | nil,
          otp_version: String.t() | nil,
          erts_version: String.t() | nil,
          app_version: String.t() | nil,
          current_screen: String.t() | nil,
          screen_info: map() | nil,
          assigns: map() | nil,
          memory: map() | nil,
          process_count: non_neg_integer() | nil,
          supervision_tree: list() | nil,
          latency_ms: float() | nil,
          connected_at: DateTime.t() | nil,
          error: String.t() | nil
        }

  @doc """
  Queries a remote node for all available information.

  Returns a `%DalaDev.Tui.Remote{}` struct with fetched data.
  """
  @spec query(atom()) :: t()
  def query(node) when is_atom(node) do
    base = %__MODULE__{node: node}

    base
    |> fetch_version()
    |> fetch_otp_version()
    |> fetch_screen_info()
    |> fetch_memory()
    |> fetch_process_count()
    |> fetch_latency()
  end

  @doc """
  Lists all connected remote nodes.
  """
  @spec connected_nodes() :: [atom()]
  def connected_nodes do
    Node.list(:connected)
  end

  @doc """
  Checks if a node is reachable.
  """
  @spec reachable?(atom()) :: boolean()
  def reachable?(node) do
    case :rpc.call(node, :erlang, :system_info, [:otp_release], 5_000) do
      {:badrpc, _} -> false
      _ -> true
    end
  end

  @doc """
  Gets the dala framework version from a remote node.
  """
  @spec get_dala_version(atom()) :: {:ok, String.t()} | {:error, term()}
  def get_dala_version(node) do
    case :rpc.call(node, Application, :spec, [:dala, :vsn], 5_000) do
      {:badrpc, reason} -> {:error, reason}
      vsn when is_list(vsn) -> {:ok, to_string(vsn)}
      nil -> {:error, :dala_not_loaded}
      other -> {:ok, inspect(other)}
    end
  end

  @doc """
  Gets the app version from a remote node.
  """
  @spec get_app_version(atom()) :: {:ok, String.t()} | {:error, term()}
  def get_app_version(node) do
    case :rpc.call(node, Application, :spec, [:vsn], 5_000) do
      {:badrpc, reason} -> {:error, reason}
      vsn when is_list(vsn) -> {:ok, to_string(vsn)}
      nil -> {:error, :no_version}
      other -> {:ok, inspect(other)}
    end
  end

  @doc """
  Gets current screen info from a remote node via Dala.Test.
  """
  @spec get_screen_info(atom()) :: {:ok, map()} | {:error, term()}
  def get_screen_info(node) do
    case :rpc.call(node, Dala.Test, :screen_info, [node], 5_000) do
      {:badrpc, reason} -> {:error, reason}
      result when is_map(result) -> {:ok, result}
      other -> {:ok, %{raw: other}}
    end
  end

  @doc """
  Gets current screen name from a remote node.
  """
  @spec get_current_screen(atom()) :: {:ok, String.t()} | {:error, term()}
  def get_current_screen(node) do
    case :rpc.call(node, Dala.Test, :screen, [node], 5_000) do
      {:badrpc, reason} -> {:error, reason}
      screen when is_atom(screen) -> {:ok, screen |> Module.split() |> List.last()}
      other -> {:ok, inspect(other)}
    end
  end

  @doc """
  Gets assigns from the current screen on a remote node.
  """
  @spec get_assigns(atom()) :: {:ok, map()} | {:error, term()}
  def get_assigns(node) do
    case :rpc.call(node, Dala.Test, :assigns, [node], 5_000) do
      {:badrpc, reason} -> {:error, reason}
      assigns when is_map(assigns) -> {:ok, assigns}
      _ -> {:ok, %{}}
    end
  end

  @doc """
  Gets memory usage from a remote node.
  """
  @spec get_memory(atom()) :: {:ok, map()} | {:error, term()}
  def get_memory(node) do
    case :rpc.call(node, :erlang, :memory, [], 5_000) do
      {:badrpc, reason} -> {:error, reason}
      memory when is_list(memory) -> {:ok, Map.new(memory)}
      _ -> %{}
    end
  end

  @doc """
  Gets process count from a remote node.
  """
  @spec get_process_count(atom()) :: non_neg_integer()
  def get_process_count(node) do
    case :rpc.call(node, :erlang, :system_info, [:process_count], 5_000) do
      {:badrpc, _} -> 0
      count when is_integer(count) -> count
      _ -> 0
    end
  end

  @doc """
  Gets the supervision tree from a remote node via DalaDev.Remote.
  """
  @spec get_supervision_tree(atom()) :: {:ok, list()} | {:error, term()}
  def get_supervision_tree(_node) do
    case DalaDev.Remote.Debugger.supervision_tree(timeout: 5_000) do
      {:ok, tree} -> {:ok, tree}
      error -> {:error, error}
    end
  rescue
    _ -> {:error, :timeout}
  end

  @doc """
  Measures latency to a remote node.
  """
  @spec measure_latency(atom()) :: {:ok, float()} | {:error, term()}
  def measure_latency(node) do
    start = System.monotonic_time(:microsecond)

    case :rpc.call(node, :erlang, :timestamp, [], 5_000) do
      {:badrpc, reason} ->
        {:error, reason}

      _ ->
        elapsed = System.monotonic_time(:microsecond) - start
        {:ok, elapsed / 1000}
    end
  end

  @doc """
  Evaluates an expression on a remote node.
  """
  @spec eval(atom(), String.t()) :: {:ok, term()} | {:error, term()}
  def eval(node, code) do
    case :rpc.call(node, Code, :eval_string, [code], 5_000) do
      {:badrpc, reason} -> {:error, reason}
      {value, _binding} -> {:ok, value}
      other -> {:ok, other}
    end
  end

  # ── Private ──────────────────────────────────────────────────

  defp fetch_version(%__MODULE__{node: node} = remote) do
    case get_dala_version(node) do
      {:ok, version} -> %{remote | version: version}
      {:error, reason} -> %{remote | error: "dala: #{inspect(reason)}"}
    end
  end

  defp fetch_otp_version(%__MODULE__{node: node} = remote) do
    case :rpc.call(node, :erlang, :system_info, [:otp_release], 5_000) do
      {:badrpc, _} -> remote
      version when is_binary(version) -> %{remote | otp_version: version}
      other -> %{remote | otp_version: inspect(other)}
    end
  end

  defp fetch_screen_info(%__MODULE__{node: node} = remote) do
    case get_screen_info(node) do
      {:ok, info} ->
        %{remote | screen_info: info}

      {:error, _} ->
        # Try to get at least the current screen name
        case get_current_screen(node) do
          {:ok, screen} -> %{remote | current_screen: screen}
          _ -> remote
        end
    end
  end

  defp fetch_memory(%__MODULE__{node: node} = remote) do
    case get_memory(node) do
      {:ok, memory} -> %{remote | memory: memory}
      _ -> remote
    end
  end

  defp fetch_process_count(%__MODULE__{node: node} = remote) do
    count = get_process_count(node)
    %{remote | process_count: count}
  end

  defp fetch_latency(%__MODULE__{node: node} = remote) do
    case measure_latency(node) do
      {:ok, ms} -> %{remote | latency_ms: ms}
      _ -> remote
    end
  end
end
