defmodule DalaDev.Server.ObserverLive.System do
  @moduledoc "LiveView for system information display."
  use Phoenix.LiveView, layout: {DalaDev.Server.Layouts, :app}
  alias DalaDev.Observer

  @refresh_interval 5_000

  @impl true
  @spec mount(term(), term(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_interval, self(), :refresh)

    socket =
      socket
      |> assign(:node, Node.self())
      |> assign(:available_nodes, [Node.self() | Node.list()])
      |> assign(:system_info, %{})
      |> assign(:error, nil)
      |> assign(:loading, false)

    {:ok, fetch_system(socket)}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(%{"node" => node_str}, _uri, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_system()}
    rescue
      _ -> {:noreply, assign(socket, :error, "Invalid node name: #{node_str}")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:refresh, socket), do: {:noreply, fetch_system(socket)}

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("refresh", _params, socket), do: {:noreply, fetch_system(socket)}

  def handle_event("select_node", %{"node" => node_str}, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_system()}
    rescue
      _ -> {:noreply, assign(socket, :error, "Invalid node: #{node_str}")}
    end
  end

  @impl true
  @spec render(Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="flex justify-between items-center mb-6">
        <div class="flex items-center gap-4">
          <a href={"/observer/#{@node}"} class="text-zinc-400 hover:text-white">
            ← Back to Dashboard
          </a>
          <h1 class="text-2xl font-bold">System Info: <%= @node %></h1>
        </div>
        <button class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded"
                phx-click="refresh">
          Refresh
        </button>
      </div>

      <div class="mb-6 bg-zinc-900 rounded-lg p-4">
        <div class="flex items-center gap-4">
          <label class="text-sm text-zinc-400">Node:</label>
          <select class="bg-zinc-800 text-zinc-100 px-3 py-2 rounded border border-zinc-700"
                  phx-change="select_node">
            <%= for n <- @available_nodes do %>
              <option value={inspect(n)} selected={n == @node}><%= inspect(n) %></option>
            <% end %>
          </select>
        </div>
      </div>

      <%= if @error do %>
        <div class="bg-red-900/20 border border-red-700 p-4 rounded mb-6">
          <p class="text-red-400"><%= @error %></p>
        </div>
      <% end %>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div class="bg-zinc-900 rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Basic Information</h2>
          <dl class="space-y-3">
            <div class="flex justify-between">
              <dt class="text-zinc-400">System Version</dt>
              <dd class="font-mono text-sm"><%= @system_info[:system_version] || "N/A" %></dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-zinc-400">Uptime</dt>
              <dd><%= format_uptime(@system_info[:uptime_ms]) %></dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-zinc-400">Word Size</dt>
              <dd><%= @system_info[:wordsize] || "N/A" %> bits</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-zinc-400">Process Count</dt>
              <dd class="font-bold"><%= @system_info[:process_count] || "N/A" %></dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-zinc-400">ETS Tables</dt>
              <dd class="font-bold"><%= @system_info[:ets_tables_count] || "N/A" %></dd>
            </div>
          </dl>
        </div>

        <div class="bg-zinc-900 rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Memory Usage</h2>
          <%= if memory = @system_info[:memory] do %>
            <dl class="space-y-3">
              <%= for {key, label} <- [total: "Total", processes: "Processes", atom: "Atom", binary: "Binary", code: "Code", ets: "ETS"] do %>
                <div class="flex justify-between">
                  <dt class="text-zinc-400"><%= label %></dt>
                  <dd class="font-mono"><%= format_bytes(memory[key]) %></dd>
                </div>
              <% end %>
            </dl>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp fetch_system(socket) do
    node = socket.assigns[:node]

    socket =
      socket
      |> assign(:loading, true)
      |> assign(:available_nodes, [Node.self() | Node.list()])

    case Observer.system_info(node) do
      info when is_map(info) ->
        assign(socket, :system_info, info)
        |> assign(:error, nil)
        |> assign(:loading, false)

      _ ->
        assign(socket, :error, "Failed to get system info for #{inspect(node)}")
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
