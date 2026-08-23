defmodule DalaDev.Server.ObserverLive.Load do
  @moduledoc "LiveView for system load display (scheduler usage, I/O stats)."

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
      |> assign(:load, %{})
      |> assign(:error, nil)
      |> assign(:loading, false)

    {:ok, fetch_load(socket)}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(%{"node" => node_str}, _uri, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_load()}
    rescue
      _ -> {:noreply, assign(socket, :error, "Invalid node name: #{node_str}")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:refresh, socket), do: {:noreply, fetch_load(socket)}

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("refresh", _params, socket), do: {:noreply, fetch_load(socket)}

  def handle_event("select_node", %{"node" => node_str}, socket) do
    try do
      node = node_str |> String.trim_leading(":") |> String.to_existing_atom()
      {:noreply, assign(socket, :node, node) |> fetch_load()}
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
          <h1 class="text-2xl font-bold">System Load: <%= @node %></h1>
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

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="bg-zinc-900 rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Scheduler Usage</h2>
          <div class="space-y-3">
            <%= for {scheduler, usage} <- @load[:scheduler_usage] || [] do %>
              <div>
                <div class="flex justify-between text-sm mb-1">
                  <span class="text-zinc-300"><%= inspect(scheduler) %></span>
                  <span class="text-zinc-400"><%= Float.round(usage, 1) %>%</span>
                </div>
                <div class="w-full bg-zinc-800 rounded-full h-4 overflow-hidden">
                  <div class="bg-blue-600 h-full rounded-full" style={"width: #{usage}%"}></div>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="bg-zinc-900 rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">I/O Statistics</h2>
          <%= if io = @load[:io] do %>
            <dl class="space-y-3">
              <div class="flex justify-between">
                <dt class="text-zinc-400">Input</dt>
                <dd class="font-mono"><%= format_bytes(elem(io, 0)) %></dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-zinc-400">Output</dt>
                <dd class="font-mono"><%= format_bytes(elem(io, 1)) %></dd>
              </div>
            </dl>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp fetch_load(socket) do
    node = socket.assigns[:node]

    socket =
      socket |> assign(:loading, true) |> assign(:available_nodes, [Node.self() | Node.list()])

    case Observer.observe(node) do
      {:ok, data} ->
        load = data[:load] || %{}
        assign(socket, :load, load) |> assign(:error, nil) |> assign(:loading, false)

      {:error, reason} ->
        assign(socket, :error, "Failed: #{reason}") |> assign(:loading, false)
    end
  end

  defp format_bytes(nil), do: "0 B"
  defp format_bytes(bytes) when is_integer(bytes) and bytes < 1024, do: "#{bytes} B"

  defp format_bytes(bytes) when is_integer(bytes) and bytes < 1024 * 1024,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when is_integer(bytes),
    do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"

  # :erlang.statistics(:io) returns {{:input, n}, {:output, n}} — the template
  # passes elem(io, 0) which is the tagged tuple, not a byte count.
  defp format_bytes({:input, n}), do: format_bytes(n)
  defp format_bytes({:output, n}), do: format_bytes(n)
  defp format_bytes(_), do: "N/A"
end
