defmodule DalaDev.Server.ObserverLive.Tracing do
  @moduledoc """
  LiveView for process tracing and message flow analysis.
  """
  use Phoenix.LiveView, layout: {DalaDev.Server.Layouts, :app}

  # alias DalaDev.{Observer, Tracing} - currently unused

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
      |> assign(:traces, [])
      |> assign(:error, nil)
      |> assign(:loading, false)

    {:ok, fetch_traces(socket)}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(%{"node" => node_str}, _uri, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_traces()}
    rescue
      _ -> {:noreply, assign(socket, :error, "Invalid node name: #{node_str}")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:refresh, socket), do: {:noreply, fetch_traces(socket)}

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("refresh", _params, socket), do: {:noreply, fetch_traces(socket)}

  def handle_event("select_node", %{"node" => node_str}, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_traces()}
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
          <a href={"/observer/#{@node}"} class="text-zinc-400 hover:text-white">← Back</a>
          <h1 class="text-2xl font-bold">Tracing: <%= @node %></h1>
        </div>
        <button class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded" phx-click="refresh">Refresh</button>
      </div>

      <div class="mb-6 bg-zinc-900 rounded-lg p-4">
        <div class="flex items-center gap-4">
          <label class="text-sm text-zinc-400">Node:</label>
          <select class="bg-zinc-800 text-zinc-100 px-3 py-2 rounded border border-zinc-700" phx-change="select_node">
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

      <div class="bg-zinc-900 rounded-lg p-6">
        <h2 class="text-xl font-semibold mb-4">Active Traces</h2>
        <%= if @traces == [] do %>
          <p class="text-zinc-400">No active traces. Start a trace by selecting a process from the Processes tab.</p>
        <% else %>
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-zinc-700">
                <th class="text-left p-3">Trace ID</th>
                <th class="text-left p-3">Process</th>
                <th class="text-left p-3">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for trace <- @traces do %>
                <tr class="border-b border-zinc-800">
                  <td class="p-3 font-mono text-xs"><%= trace.id %></td>
                  <td class="p-3"><%= trace.process || "-" %></td>
                  <td class="p-3">
                    <button class="px-3 py-1 bg-red-600 hover:bg-red-700 rounded text-sm"
                            phx-click="stop_trace" phx-value-trace_id={trace.id}>
                      Stop
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>
    </div>
    """
  end

  defp fetch_traces(socket) do
    socket =
      socket |> assign(:loading, true) |> assign(:available_nodes, [Node.self() | Node.list()])

    traces = []
    assign(socket, :traces, traces) |> assign(:error, nil) |> assign(:loading, false)
  end
end
