defmodule DalaDev.Server.ObserverLive.Processes do
  @moduledoc """
  LiveView for process list display with sorting and filtering.
  """
  use Phoenix.LiveView, layout: {DalaDev.Server.Layouts, :app}

  alias DalaDev.Observer

  @refresh_interval 5_000
  @page_size 100

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
      |> assign(:processes, [])
      |> assign(:filtered_processes, [])
      |> assign(:error, nil)
      |> assign(:loading, false)
      |> assign(:sort_by, "memory")
      |> assign(:sort_order, :desc)
      |> assign(:filter, "")
      |> assign(:selected_pid, nil)

    {:ok, fetch_processes(socket)}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(%{"node" => node_str}, _uri, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_processes()}
    rescue
      _ -> {:noreply, assign(socket, :error, "Invalid node name: #{node_str}")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:refresh, socket), do: {:noreply, fetch_processes(socket)}

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("refresh", _params, socket), do: {:noreply, fetch_processes(socket)}

  def handle_event("select_node", %{"node" => node_str}, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_processes()}
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

  def handle_event("select_process", %{"pid" => pid_str}, socket) do
    {:noreply, assign(socket, :selected_pid, pid_str)}
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
          <h1 class="text-2xl font-bold">Processes: <%= @node %></h1>
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
            <input type="text" placeholder="Filter by PID, name, or function..."
                   class="w-full bg-zinc-800 text-zinc-100 px-3 py-2 rounded border border-zinc-700"
                   phx-change="filter" phx-value-filter="" value={@filter} />
          </div>

          <span class="text-sm text-zinc-500">
            <%= length(@filtered_processes) %> / <%= length(@processes) %> processes
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

      <div class="bg-zinc-900 rounded-lg overflow-hidden">
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-zinc-700 bg-zinc-800">
              <th class="text-left p-3">PID</th>
              <th class="text-left p-3">Name</th>
              <th class="text-right p-3 cursor-pointer hover:bg-zinc-700"
                  phx-click="sort" phx-value-by="memory">
                Memory <%= if @sort_by == "memory", do: sort_indicator(@sort_order) %>
              </th>
              <th class="text-right p-3 cursor-pointer hover:bg-zinc-700"
                  phx-click="sort" phx-value-by="reductions">
                Reductions <%= if @sort_by == "reductions", do: sort_indicator(@sort_order) %>
              </th>
              <th class="text-right p-3 cursor-pointer hover:bg-zinc-700"
                  phx-click="sort" phx-value-by="message_queue">
                Msg Queue <%= if @sort_by == "message_queue", do: sort_indicator(@sort_order) %>
              </th>
              <th class="text-left p-3">Current Function</th>
              <th class="text-left p-3">Status</th>
            </tr>
          </thead>
          <tbody>
            <%= for proc <- @filtered_processes do %>
              <tr class={"border-b border-zinc-800 hover:bg-zinc-800 cursor-pointer " <>
                      (if @selected_pid == proc.pid, do: "bg-zinc-800", else: "")}
                  phx-click="select_process" phx-value-pid={proc.pid}>
                <td class="p-3 font-mono text-xs"><%= proc.pid %></td>
                <td class="p-3"><%= proc.name || proc.registered_name || "-" %></td>
                <td class="p-3 text-right"><%= format_bytes(proc.memory) %></td>
                <td class="p-3 text-right"><%= format_number(proc.reductions) %></td>
                <td class="p-3 text-right">
                  <span class={if proc.message_queue_len > 0, do: "text-yellow-400", else: ""}>
                    <%= proc.message_queue_len %>
                  </span>
                </td>
                <td class="p-3 font-mono text-xs text-zinc-400"><%= proc.current_function %></td>
                <td class="p-3">
                  <span class={"px-2 py-1 text-xs rounded " <>
                    (if proc.status == :running, do: "bg-green-900 text-green-300",
                     else: "bg-zinc-700 text-zinc-300")}>
                    <%= proc.status %>
                  </span>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%= if @selected_pid && find_process(@processes, @selected_pid) do %>
        <% proc = find_process(@processes, @selected_pid) %>
        <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
             phx-click="select_process" phx-value-pid="">
          <div class="bg-zinc-900 rounded-lg p-6 max-w-2xl w-full mx-4"
               phx-click-away="select_process" phx-value-pid="">
            <h2 class="text-xl font-semibold mb-4">Process Details</h2>
            <dl class="space-y-2">
              <div class="flex justify-between">
                <dt class="text-zinc-400">PID</dt>
                <dd class="font-mono"><%= proc.pid %></dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-zinc-400">Name</dt>
                <dd><%= proc.name || proc.registered_name || "-" %></dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-zinc-400">Memory</dt>
                <dd><%= format_bytes(proc.memory) %></dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-zinc-400">Reductions</dt>
                <dd><%= format_number(proc.reductions) %></dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-zinc-400">Message Queue</dt>
                <dd><%= proc.message_queue_len %></dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-zinc-400">Current Function</dt>
                <dd class="font-mono text-sm"><%= proc.current_function %></dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-zinc-400">Status</dt>
                <dd><%= proc.status %></dd>
              </div>
            </dl>
            <button class="mt-4 px-4 py-2 bg-zinc-700 hover:bg-zinc-600 rounded"
                    phx-click="select_process" phx-value-pid="">
              Close
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp fetch_processes(socket) do
    node = socket.assigns[:node]

    socket =
      socket
      |> assign(:loading, true)
      |> assign(:available_nodes, [Node.self() | Node.list()])

    case Observer.process_list(node) do
      processes when is_list(processes) ->
        socket
        |> assign(:processes, processes)
        |> assign(:error, nil)
        |> assign(:loading, false)
        |> apply_sort_and_filter()

      _ ->
        assign(socket, :error, "Failed to get process list for #{inspect(node)}")
        |> assign(:loading, false)
    end
  end

  defp apply_sort_and_filter(socket) do
    processes = socket.assigns[:processes]
    sort_by = socket.assigns[:sort_by]
    sort_order = socket.assigns[:sort_order]
    filter = socket.assigns[:filter]

    filtered =
      processes
      |> Enum.filter(&matches_filter?(&1, filter))
      |> sort_processes(sort_by, sort_order)
      |> Enum.take(@page_size)

    assign(socket, :filtered_processes, filtered)
  end

  defp sort_processes(processes, "memory", :desc), do: Enum.sort_by(processes, & &1.memory, &>=/2)
  defp sort_processes(processes, "memory", :asc), do: Enum.sort_by(processes, & &1.memory, &<=/2)

  defp sort_processes(processes, "reductions", :desc),
    do: Enum.sort_by(processes, & &1.reductions, &>=/2)

  defp sort_processes(processes, "reductions", :asc),
    do: Enum.sort_by(processes, & &1.reductions, &<=/2)

  defp sort_processes(processes, "message_queue", :desc),
    do: Enum.sort_by(processes, & &1.message_queue_len, &>=/2)

  defp sort_processes(processes, "message_queue", :asc),
    do: Enum.sort_by(processes, & &1.message_queue_len, &<=/2)

  defp sort_processes(processes, _, _), do: processes

  defp matches_filter?(_proc, ""), do: true

  defp matches_filter?(proc, filter) do
    String.contains?(proc.pid, filter) ||
      (proc.name && String.contains?(proc.name, filter)) ||
      (proc.registered_name && String.contains?(proc.registered_name, filter)) ||
      String.contains?(proc.current_function, filter)
  end

  defp toggle_order(:asc), do: :desc
  defp toggle_order(:desc), do: :asc

  defp find_process(processes, pid) do
    Enum.find(processes, &(&1.pid == pid))
  end

  defp format_bytes(nil), do: "0 B"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"

  defp format_number(n) when n < 1000, do: "#{n}"
  defp format_number(n) when n < 1_000_000, do: "#{Float.round(n / 1000, 1)}K"
  defp format_number(n), do: "#{Float.round(n / 1_000_000, 1)}M"

  defp sort_indicator(:asc), do: " ↑"
  defp sort_indicator(:desc), do: " ↓"
end
