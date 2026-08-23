defmodule DalaDev.Observer do
  @moduledoc """
  Remote node observer inspired by `:observer.start()`.

  Collects comprehensive system information from remote nodes and provides
  data structures suitable for LiveView rendering. This includes:

  - System information (memory, CPU, uptime)
  - Process list with detailed statistics
  - ETS tables information
  - Application controller state
  - Loaded modules and memory
  - Port information
  - Node connectivity status

  All data is collected via RPC calls to remote nodes, making it suitable
  for monitoring dala Elixir nodes that don't have direct access to
  `:observer`.
  """

  # alias DalaDev.Network - currently unused

  @type process_info :: %{
          pid: String.t(),
          name: String.t() | nil,
          memory: integer(),
          reductions: integer(),
          message_queue_len: integer(),
          current_function: String.t(),
          status: atom(),
          registered_name: String.t() | nil
        }

  @type system_info :: %{
          memory: map(),
          statistics: map(),
          system_version: String.t(),
          uptime_ms: integer(),
          process_count: integer(),
          ets_tables_count: integer()
        }

  @doc """
  Get comprehensive system information from a node.

  Returns all observable data from the specified node.
  """
  @spec observe(node(), keyword()) :: {:ok, map()} | {:error, term()}
  def observe(node \\ Node.self(), opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)

    try do
      data = %{
        node: node,
        timestamp: DateTime.utc_now(),
        system: fetch_system_info(node, timeout),
        processes: fetch_processes(node, timeout),
        ets_tables: fetch_ets_tables(node, timeout),
        applications: fetch_applications(node, timeout),
        modules: fetch_modules_info(node, timeout),
        ports: fetch_ports(node, timeout),
        load: fetch_load(node, timeout)
      }

      {:ok, data}
    rescue
      e -> {:error, Exception.message(e)}
    catch
      :exit, reason -> {:error, "Node #{inspect(node)} unreachable: #{inspect(reason)}"}
    end
  end

  @doc """
  Get system-level information (memory, stats, version).
  """
  @spec system_info(node(), integer()) :: system_info()
  def system_info(node \\ Node.self(), timeout \\ 10_000) do
    fetch_system_info(node, timeout)
  end

  @doc """
  Get detailed process list with statistics.
  """
  @spec process_list(node(), integer()) :: [process_info()]
  def process_list(node \\ Node.self(), timeout \\ 10_000) do
    fetch_processes(node, timeout)
  end

  @doc """
  Get ETS tables information.
  """
  @spec ets_tables(node(), integer()) :: [map()]
  def ets_tables(node \\ Node.self(), timeout \\ 10_000) do
    fetch_ets_tables(node, timeout)
  end

  # ── Private: Data Collection ─────────────────────

  defp fetch_system_info(node, _timeout) do
    call_remote(node, fn ->
      memory = :erlang.memory() |> Enum.into(%{})
      stats = :erlang.statistics(:runtime) |> elem(0)

      %{
        memory: %{
          total: memory[:total] || 0,
          processes: memory[:processes] || 0,
          atom: memory[:atom] || 0,
          binary: memory[:binary] || 0,
          code: memory[:code] || 0,
          ets: memory[:ets] || 0
        },
        statistics: %{
          runtime: stats
        },
        system_version: to_string(:erlang.system_info(:system_version)),
        uptime_ms: :erlang.statistics(:wall_clock) |> elem(0),
        process_count: :erlang.system_info(:process_count),
        ets_tables_count: :ets.all() |> length(),
        wordsize: :erlang.system_info(:wordsize)
      }
    end)
  end

  defp fetch_processes(node, _timeout) do
    call_remote(node, fn ->
      :erlang.processes()
      |> Enum.map(fn pid ->
        try do
          info =
            Process.info(pid, [
              :memory,
              :reductions,
              :message_queue_len,
              :current_function,
              :status,
              :registered_name
            ])

          %{
            pid: inspect(pid),
            name: format_process_name(pid, info[:registered_name]),
            memory: info[:memory] || 0,
            reductions: info[:reductions] || 0,
            message_queue_len: info[:message_queue_len] || 0,
            current_function: format_mfa(info[:current_function]),
            status: info[:status],
            registered_name: format_registered_name(info[:registered_name])
          }
        rescue
          _ -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.sort_by(& &1.memory, &>=/2)
    end)
  end

  defp fetch_ets_tables(node, _timeout) do
    call_remote(node, fn ->
      :ets.all()
      |> Enum.map(fn tid ->
        try do
          info = :ets.info(tid)

          %{
            id: inspect(tid),
            name: to_string(info[:name] || ""),
            type: info[:type],
            size: info[:size] || 0,
            memory: info[:memory] || 0,
            owner: inspect(info[:owner] || ""),
            heir: inspect(info[:heir] || ""),
            protection: info[:protection]
          }
        rescue
          _ -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.sort_by(& &1.memory, &>=/2)
    end)
  end

  defp fetch_applications(node, _timeout) do
    call_remote(node, fn ->
      :application.which_applications()
      |> Enum.map(fn {name, desc, version} ->
        %{
          name: to_string(name),
          description: to_string(desc),
          version: to_string(version)
        }
      end)
    end)
  end

  defp fetch_modules_info(node, _timeout) do
    call_remote(node, fn ->
      modules = :code.all_loaded()

      total_memory =
        modules
        |> Enum.map(fn {_, beam_path} ->
          if beam_path != :preloaded, do: file_size(beam_path), else: 0
        end)
        |> Enum.sum()

      %{
        count: length(modules),
        total_memory: total_memory,
        modules:
          modules
          |> Enum.take(100)
          |> Enum.map(fn {mod, path} ->
            %{
              module: inspect(mod),
              path: to_string(path)
            }
          end)
      }
    end)
  end

  defp fetch_ports(node, _timeout) do
    call_remote(node, fn ->
      :erlang.ports()
      |> Enum.map(fn port ->
        try do
          info = Port.info(port)

          %{
            id: inspect(port),
            name: to_string(info[:name] || ""),
            os_pid: info[:os_pid],
            connected: inspect(info[:connected] || ""),
            input: info[:input] || 0,
            output: info[:output] || 0
          }
        rescue
          _ -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
    end)
  end

  defp fetch_load(node, _timeout) do
    call_remote(node, fn ->
      %{
        scheduler_usage:
          try do
            sample = apply(:scheduler, :sample, [])
            apply(:scheduler, :usage, [sample])
          rescue
            _ -> []
          end,
        io: :erlang.statistics(:io)
      }
    end)
  end

  # ── Private: Helpers ─────────────────────────────

  @spec call_remote(node(), (-> term())) :: term()
  def call_remote(node, fun) do
    if node == Node.self() do
      fun.()
    else
      case Node.connect(node) do
        true ->
          case :rpc.call(node, __MODULE__, :execute_remote, [fun], 10_000) do
            {:badrpc, reason} -> %{error: "RPC failed: #{inspect(reason)}"}
            result -> result
          end

        false ->
          %{error: "Cannot connect to node #{inspect(node)}"}
      end
    end
  end

  @doc false
  @spec execute_remote((-> term())) :: term()
  def execute_remote(fun) do
    fun.()
  end

  defp format_process_name(_pid, :undefined), do: nil
  defp format_process_name(_pid, name), do: to_string(name)

  defp format_registered_name(:undefined), do: nil
  defp format_registered_name(name), do: to_string(name)

  defp format_mfa({mod, fun, arity}) do
    "#{inspect(mod)}.#{fun}/#{arity}"
  end

  defp format_mfa(_), do: "unknown"

  defp file_size(path) when is_list(path) do
    case File.stat(to_string(path)) do
      {:ok, %File.Stat{size: size}} -> size
      _ -> 0
    end
  end

  defp file_size(_), do: 0
end
