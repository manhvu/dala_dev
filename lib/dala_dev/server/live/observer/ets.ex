defmodule DalaDev.Server.ObserverLive.ETS do
  @moduledoc "LiveView for ETS tables browser."
  use Phoenix.LiveView, layout: {DalaDev.Server.Layouts, :app}
  alias DalaDev.Observer

  @refresh_interval 5_000
  @page_size 100

  @impl true
  @spec mount(term(), term(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_interval, self(), :refresh)

    socket =
      socket
      |> assign(:node, Node.self())
      |> assign(:available_nodes, [Node.self() | Node.list()])
      |> assign(:tables, [])
      |> assign(:filtered_tables, [])
      |> assign(:error, nil)
      |> assign(:loading, false)
      |> assign(:sort_by, "memory")
      |> assign(:sort_order, :desc)
      |> assign(:filter, "")
      |> assign(:selected_table, nil)

    {:ok, fetch_tables(socket)}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(%{"node" => node_str}, _uri, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_tables()}
    rescue
      _ -> {:noreply, assign(socket, :error, "Invalid node name: #{node_str}")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:refresh, socket), do: {:noreply, fetch_tables(socket)}

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("refresh", _params, socket), do: {:noreply, fetch_tables(socket)}

  def handle_event("select_node", %{"node" => node_str}, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_tables()}
    rescue
      _ -> {:noreply, assign(socket, :error, "Invalid node: #{node_str}")}
    end
  end

  def handle_event("sort", %{"by" => sort_by}, socket) do
    current_sort = socket.assigns[:sort_by]

    {new_sort, new_order} =
      if sort_by == current_sort do
        {sort_by, toggle_order(socket.assigns[:sort_order])}
      else
        {sort_by, :desc}
      end

    socket =
      socket
      |> assign(:sort_by, new_sort)
      |> assign(:sort_order, new_order)

    {:noreply, apply_sort_and_filter(socket)}
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, assign(socket, :filter, filter) |> apply_sort_and_filter()}
  end

  def handle_event("select_table", %{"id" => table_id}, socket) do
    {:noreply, assign(socket, :selected_table, table_id)}
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
          <h1 class="text-2xl font-bold">ETS Tables: <%= @node %></h1>
        </div>
        <button class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded"
                phx-click="refresh">
          Refresh
        </button>
      </div>

      <div class="mb-6 bg-zinc-900 rounded-lg p-4">
        <div class="flex flex-wrap items-center gap-4">
          <div class="flex items-center gap-2">
            <label class="text-sm text-zinc-400">Node:</label>
            <select class="bg-zinc-800 text-zinc-100 px-3 py-2 rounded border border-zinc-700"
                    phx-change="select_node">
              <%= for n <- @available_nodes do %>
                <option value={inspect(n)} selected={n == @node}><%= inspect(n) %></option>
              <% end %>
            </select>
          </div>

          <div class="flex-1 max-w-md">
            <input type="text" placeholder="Filter by name or ID..."
                   class="w-full bg-zinc-800 text-zinc-100 px-3 py-2 rounded border border-zinc-700"
                   phx-change="filter" phx-value-filter="" value={@filter} />
          </div>

          <span class="text-sm text-zinc-500">
            <%= length(@filtered_tables) %> / <%= length(@tables) %> tables
          </span>
        </div>
      </div>

      <%= if @error do %>
        <div class="bg-red-900/20 border border-red-700 p-4 rounded mb-6">
          <p class="text-red-400"><%= @error %></p>
        </div>
      <% end %>

      <div class="bg-zinc-900 rounded-lg overflow-hidden">
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-zinc-700 bg-zinc-800">
              <th class="text-left p-3">ID</th>
              <th class="text-left p-3">Name</th>
              <th class="text-left p-3">Type</th>
              <th class="text-right p-3">Size</th>
              <th class="text-right p-3">Memory</th>
              <th class="text-left p-3">Owner</th>
              <th class="text-left p-3">Protection</th>
            </tr>
          </thead>
          <tbody>
            <%= for table <- @filtered_tables do %>
              <tr class={"border-b border-zinc-800 hover:bg-zinc-800 cursor-pointer " <>
                      (if @selected_table == table.id, do: "bg-zinc-800", else: "")}
                  phx-click="select_table" phx-value-id={table.id}>
                <td class="p-3 font-mono text-xs"><%= table.id %></td>
                <td class="p-3"><%= table.name %></td>
                <td class="p-3"><%= table.type %></td>
                <td class="p-3 text-right"><%= format_number(table.size) %></td>
                <td class="p-3 text-right"><%= format_bytes(table.memory) %></td>
                <td class="p-3 font-mono text-xs"><%= table.owner %></td>
                <td class="p-3"><%= table.protection %></td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp fetch_tables(socket) do
    node = socket.assigns[:node]

    socket =
      socket
      |> assign(:loading, true)
      |> assign(:available_nodes, [Node.self() | Node.list()])

    case Observer.ets_tables(node) do
      tables when is_list(tables) ->
        socket
        |> assign(:tables, tables)
        |> assign(:error, nil)
        |> assign(:loading, false)
        |> apply_sort_and_filter()

      _ ->
        assign(socket, :error, "Failed to get ETS tables for #{inspect(node)}")
        |> assign(:loading, false)
    end
  end

  defp apply_sort_and_filter(socket) do
    tables = socket.assigns[:tables]
    sort_by = socket.assigns[:sort_by]
    sort_order = socket.assigns[:sort_order]
    filter = socket.assigns[:filter]

    filtered =
      tables
      |> Enum.filter(&matches_filter?(&1, filter))
      |> sort_tables(sort_by, sort_order)
      |> Enum.take(@page_size)

    assign(socket, :filtered_tables, filtered)
  end

  defp sort_tables(tables, "memory", :desc), do: Enum.sort_by(tables, & &1.memory, &>=/2)
  defp sort_tables(tables, "memory", :asc), do: Enum.sort_by(tables, & &1.memory, &<=/2)
  defp sort_tables(tables, "size", :desc), do: Enum.sort_by(tables, & &1.size, &>=/2)
  defp sort_tables(tables, "size", :asc), do: Enum.sort_by(tables, & &1.size, &<=/2)
  defp sort_tables(tables, _, _), do: tables

  defp matches_filter?(_table, ""), do: true

  defp matches_filter?(table, filter) do
    String.contains?(table.id, filter) ||
      String.contains?(table.name, filter)
  end

  defp toggle_order(:asc), do: :desc
  defp toggle_order(:desc), do: :asc

  defp format_bytes(nil), do: "0 B"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"

  defp format_number(n) when n < 1000, do: "#{n}"
  defp format_number(n) when n < 1_000_000, do: "#{Float.round(n / 1000, 1)}K"
  defp format_number(n), do: "#{Float.round(n / 1_000_000, 1)}M"
end
