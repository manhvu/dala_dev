defmodule DalaDev.Server.ObserverLive.Applications do
  @moduledoc "LiveView for applications list display."

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
      |> assign(:applications, [])
      |> assign(:error, nil)
      |> assign(:loading, false)

    {:ok, fetch_applications(socket)}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(%{"node" => node_str}, _uri, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_applications()}
    rescue
      _ -> {:noreply, assign(socket, :error, "Invalid node name: #{node_str}")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:refresh, socket), do: {:noreply, fetch_applications(socket)}

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("refresh", _params, socket), do: {:noreply, fetch_applications(socket)}

  def handle_event("select_node", %{"node" => node_str}, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_applications()}
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
          <h1 class="text-2xl font-bold">Applications: <%= @node %></h1>
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

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for app <- @applications do %>
          <div class="bg-zinc-900 rounded-lg p-4">
            <h3 class="font-semibold text-lg"><%= app.name %></h3>
            <p class="text-sm text-zinc-400 mt-1"><%= app.description %></p>
            <p class="text-xs text-zinc-500 mt-2">Version: <%= app.version %></p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp fetch_applications(socket) do
    node = socket.assigns[:node]

    socket =
      socket |> assign(:loading, true) |> assign(:available_nodes, [Node.self() | Node.list()])

    case Observer.observe(node) do
      {:ok, data} ->
        apps = data[:applications] || []
        assign(socket, :applications, apps) |> assign(:error, nil) |> assign(:loading, false)

      {:error, reason} ->
        assign(socket, :error, "Failed: #{reason}") |> assign(:loading, false)
    end
  end
end
