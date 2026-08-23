defmodule DalaDev.Server.ObserverLive do
  @moduledoc """
  Main Observer dashboard with navigation to specialized views.

  Provides an overview of all nodes and quick access to detailed views
  for system info, processes, ETS tables, applications, etc.
  """

  use Phoenix.LiveView, layout: {DalaDev.Server.Layouts, :app}

  alias DalaDev.Observer

  @refresh_interval 5_000

  @impl true
  @spec mount(term(), term(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_interval, self(), :refresh)
    end

    socket =
      socket
      |> assign(:node, Node.self())
      |> assign(:available_nodes, [Node.self() | Node.list()])
      |> assign(:summary, nil)
      |> assign(:error, nil)
      |> assign(:loading, false)

    {:ok, fetch_summary(socket)}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(%{"node" => node_str}, _uri, socket) do
    case resolve_node(node_str, socket.assigns.available_nodes) do
      {:ok, node} ->
        {:noreply, assign(socket, :node, node) |> fetch_summary()}

      :error ->
        {:noreply, assign(socket, :error, "Invalid node name: #{node_str}")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:refresh, socket) do
    {:noreply, fetch_summary(socket)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("refresh", _params, socket) do
    {:noreply, fetch_summary(socket)}
  end

  def handle_event("select_node", %{"node" => node_str}, socket) do
    case resolve_node(node_str, socket.assigns.available_nodes) do
      {:ok, node} ->
        {:noreply, assign(socket, :node, node) |> fetch_summary()}

      :error ->
        {:noreply, assign(socket, :error, "Invalid node: #{node_str}")}
    end
  end

  defp resolve_node(node_str, available_nodes) do
    case Enum.find(available_nodes, &(Atom.to_string(&1) == node_str)) do
      nil -> :error
      node -> {:ok, node}
    end
  end

  @impl true
  @spec render(Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <!-- Header -->
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-2xl font-bold">Observer: <%= @node %></h1>
        <button class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded"
                phx-click="refresh">
          Refresh
        </button>
      </div>

      <!-- Node Selector -->
      <div class="mb-6 bg-zinc-900 rounded-lg p-4">
        <div class="flex items-center gap-4">
          <label class="text-sm text-zinc-400">Node:</label>
          <select class="bg-zinc-800 text-zinc-100 px-3 py-2 rounded border border-zinc-700"
                  phx-change="select_node">
            <%= for n <- @available_nodes do %>
              <option value={Atom.to_string(n)} selected={n == @node}><%= Atom.to_string(n) %></option>
            <% end %>
          </select>
          <span class="text-sm text-zinc-500">
            <%= length(@available_nodes) %> node(s) available
          </span>
        </div>
      </div>

      <%= if @error do %>
        <div class="bg-red-900/20 border border-red-700 p-4 rounded mb-6">
          <p class="text-red-400"><%= @error %></p>
        </div>
      <% end %>

      <%= if @loading do %>
        <div class="text-center py-8 text-zinc-400">Loading...</div>
      <% end %>

      <!-- Summary Cards -->
      <%= if @summary do %>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          <div class="bg-zinc-900 rounded-lg p-4">
            <dt class="text-zinc-400 text-sm">Processes</dt>
            <dd class="text-2xl font-bold"><%= @summary.process_count || 0 %></dd>
          </div>
          <div class="bg-zinc-900 rounded-lg p-4">
            <dt class="text-zinc-400 text-sm">ETS Tables</dt>
            <dd class="text-2xl font-bold"><%= @summary.ets_tables_count || 0 %></dd>
          </div>
          <div class="bg-zinc-900 rounded-lg p-4">
            <dt class="text-zinc-400 text-sm">Memory (Total)</dt>
            <dd class="text-2xl font-bold"><%= format_bytes(@summary.memory_total) %></dd>
          </div>
          <div class="bg-zinc-900 rounded-lg p-4">
            <dt class="text-zinc-400 text-sm">Uptime</dt>
            <dd class="text-2xl font-bold"><%= format_uptime(@summary.uptime_ms) %></dd>
          </div>
        </div>
      <% end %>

      <!-- Navigation Cards -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <a href={"/observer/#{@node}/system"} class="bg-zinc-900 rounded-lg p-6 hover:bg-zinc-800 transition">
          <h2 class="text-xl font-semibold mb-2">System Info</h2>
          <p class="text-zinc-400 text-sm">Memory, uptime, version, and system statistics</p>
        </a>

        <a href={"/observer/#{@node}/processes"} class="bg-zinc-900 rounded-lg p-6 hover:bg-zinc-800 transition">
          <h2 class="text-xl font-semibold mb-2">Processes</h2>
          <p class="text-zinc-400 text-sm">Process list with sorting, filtering, and details</p>
        </a>

        <a href={"/observer/#{@node}/ets"} class="bg-zinc-900 rounded-lg p-6 hover:bg-zinc-800 transition">
          <h2 class="text-xl font-semibold mb-2">ETS Tables</h2>
          <p class="text-zinc-400 text-sm">ETS tables browser with memory and ownership info</p>
        </a>

        <a href={"/observer/#{@node}/applications"} class="bg-zinc-900 rounded-lg p-6 hover:bg-zinc-800 transition">
          <h2 class="text-xl font-semibold mb-2">Applications</h2>
          <p class="text-zinc-400 text-sm">Running applications with versions</p>
        </a>

        <a href={"/observer/#{@node}/modules"} class="bg-zinc-900 rounded-lg p-6 hover:bg-zinc-800 transition">
          <h2 class="text-xl font-semibold mb-2">Modules</h2>
          <p class="text-zinc-400 text-sm">Loaded modules and memory usage</p>
        </a>

        <a href={"/observer/#{@node}/ports"} class="bg-zinc-900 rounded-lg p-6 hover:bg-zinc-800 transition">
          <h2 class="text-xl font-semibold mb-2">Ports</h2>
          <p class="text-zinc-400 text-sm">Port information and I/O statistics</p>
        </a>

        <a href={"/observer/#{@node}/load"} class="bg-zinc-900 rounded-lg p-6 hover:bg-zinc-800 transition">
          <h2 class="text-xl font-semibold mb-2">System Load</h2>
          <p class="text-zinc-400 text-sm">Scheduler usage and I/O statistics</p>
        </a>

        <a href={"/observer/#{@node}/tracing"} class="bg-zinc-900 rounded-lg p-6 hover:bg-zinc-800 transition">
          <h2 class="text-xl font-semibold mb-2">Tracing</h2>
          <p class="text-zinc-400 text-sm">Process tracing and message flow analysis</p>
        </a>
      </div>
    </div>
    """
  end

  defp fetch_summary(socket) do
    node = socket.assigns[:node]

    socket =
      socket
      |> assign(:loading, true)
      |> assign(:available_nodes, [Node.self() | Node.list()])

    case Observer.observe(node) do
      {:ok, data} ->
        system = data[:system] || %{}
        memory = system[:memory] || %{}

        summary = %{
          process_count: system[:process_count] || 0,
          ets_tables_count: system[:ets_tables_count] || 0,
          memory_total: memory[:total] || 0,
          uptime_ms: system[:uptime_ms] || 0
        }

        assign(socket, :summary, summary)
        |> assign(:error, nil)
        |> assign(:loading, false)

      {:error, reason} ->
        assign(socket, :error, "Failed to observe #{inspect(node)}: #{reason}")
        |> assign(:loading, false)
    end
  end

  defp format_bytes(nil), do: "0 B"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"

  defp format_uptime(nil), do: "N/A"

  defp format_uptime(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    hours = div(minutes, 60)
    days = div(hours, 24)

    cond do
      days > 0 -> "#{days}d #{rem(hours, 24)}h"
      hours > 0 -> "#{hours}h #{rem(minutes, 60)}m"
      minutes > 0 -> "#{minutes}m #{rem(seconds, 60)}s"
      true -> "#{seconds}s"
    end
  end
end
