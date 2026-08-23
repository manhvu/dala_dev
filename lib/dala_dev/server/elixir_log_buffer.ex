defmodule DalaDev.Server.ElixirLogBuffer do
  @moduledoc """
  Holds the last N server-side Elixir log lines in memory so the dashboard
  can restore them on reconnect. Fed by `DalaDev.Server.ElixirLogger`.
  """
  use GenServer

  @limit 200

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get() :: [map()]
  def get, do: GenServer.call(__MODULE__, :get)

  @spec push(map()) :: :ok
  def push(line), do: GenServer.cast(__MODULE__, {:push, line})

  @spec clear() :: :ok
  def clear, do: GenServer.cast(__MODULE__, :clear)

  @impl GenServer
  @spec init(term()) :: {:ok, [map()]}
  def init(_), do: {:ok, []}

  @impl GenServer
  @spec handle_call(:get, GenServer.from(), [map()]) :: {:reply, [map()], [map()]}
  def handle_call(:get, _from, lines), do: {:reply, lines, lines}

  @impl GenServer
  @spec handle_cast({:push, map()} | :clear, [map()]) :: {:noreply, [map()]}
  def handle_cast({:push, line}, lines) do
    {:noreply, Enum.take([line | lines], @limit)}
  end

  def handle_cast(:clear, _lines), do: {:noreply, []}
end
