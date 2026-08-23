defmodule DalaDev.Server.ObserverLive.Modules do
  @moduledoc "LiveView for loaded modules display."

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
      |> assign(:modules_info, %{})
      |> assign(:error, nil)
      |> assign(:loading, false)

    {:ok, fetch_modules(socket)}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(%{"node" => node_str}, _uri, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_modules()}
    rescue
      _ -> {:noreply, assign(socket, :error, "Invalid node name: #{node_str}")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:refresh, socket), do: {:noreply, fetch_modules(socket)}

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("refresh", _params, socket), do: {:noreply, fetch_modules(socket)}

  def handle_event("select_node", %{"node" => node_str}, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_modules()}
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
          <h1 class="text-2xl font-bold">Modules: <%= @node %></h1>
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

      <div class="bg-zinc-900 rounded-lg p-6 mb-6">
        <h2 class="text-xl font-semibold mb-4">Summary</h2>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <dt class="text-zinc-400 text-sm">Total Modules</dt>
            <dd class="text-2xl font-bold"><%= @modules_info[:count] || 0 %></dd>
          </div>
          <div>
            <dt class="text-zinc-400 text-sm">Total Memory</dt>
            <dd class="text-2xl font-bold"><%= format_bytes(@modules_info[:total_memory]) %></dd>
          </div>
        </div>
      </div>

      <div class="bg-zinc-900 rounded-lg overflow-hidden">
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-zinc-700 bg-zinc-800">
              <th class="text-left p-3">Module</th>
              <th class="text-left p-3">Path</th>
            </tr>
          </thead>
          <tbody>
            <%= for mod <- @modules_info[:modules] || [] do %>
              <tr class="border-b border-zinc-800 hover:bg-zinc-800">
                <td class="p-3 font-mono text-xs"><%= mod.module %></td>
                <td class="p-3 font-mono text-xs text-zinc-400"><%= mod.path %></td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp fetch_modules(socket) do
    node = socket.assigns[:node]

    socket =
      socket |> assign(:loading, true) |> assign(:available_nodes, [Node.self() | Node.list()])

    case Observer.observe(node) do
      {:ok, data} ->
        modules = data[:modules] || %{}
        assign(socket, :modules_info, modules) |> assign(:error, nil) |> assign(:loading, false)

      {:error, reason} ->
        assign(socket, :error, "Failed: #{reason}") |> assign(:loading, false)
    end
  end

  defp format_bytes(nil), do: "0 B"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
end
