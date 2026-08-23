defmodule DalaDev.Server.ClusterVizLive do
  @moduledoc """
  LiveView for cluster visualization with D3.js.

  Provides real-time visualization of:
  - Cluster topology
  - Node health dashboard
  - Process distribution
  - LiveView message flow
  """

  use Phoenix.LiveView, layout: {DalaDev.Server.Layouts, :app}

  alias DalaDev.ClusterViz

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
      |> assign(:topology, %{})
      |> assign(:health, %{})
      |> assign(:processes, %{})
      |> assign(:flow, %{})
      |> assign(:error, nil)

    {:ok, fetch_all(socket)}
  end

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:refresh, socket) do
    {:noreply, fetch_all(socket)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("refresh", _params, socket) do
    {:noreply, fetch_all(socket)}
  end

  @impl true
  @spec render(Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-2xl font-bold">Cluster Visualization</h1>
        <button class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded"
                phx-click="refresh">
          Refresh
        </button>
      </div>

      <%= if @error do %>
        <div class="bg-red-900/20 border border-red-700 p-4 rounded mb-6">
          <p class="text-red-400"><%= @error %></p>
        </div>
      <% end %>

      <!-- Topology Visualization -->
      <div class="mb-8">
        <h2 class="text-xl font-semibold mb-4">Cluster Topology</h2>
        <div class="bg-zinc-900 rounded-lg p-4" style="height: 400px;">
          <div id="topology-chart" class="w-full h-full"
               phx-hook="ClusterTopology"
               data-nodes={Jason.encode!(@topology[:nodes] || [])}
               data-connections={Jason.encode!(@topology[:connections] || [])}>
          </div>
        </div>
      </div>

      <!-- Node Health Dashboard -->
      <div class="mb-8">
        <h2 class="text-xl font-semibold mb-4">Node Health</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <%= for node_data <- @health[:nodes] || [] do %>
            <div class="bg-zinc-900 rounded-lg p-4">
              <div class="flex justify-between items-center mb-2">
                <h3 class="font-semibold"><%= node_data.node %></h3>
                <span class={"px-2 py-1 text-xs rounded " <>
                  (if node_data.status == :alive, do: "bg-green-900 text-green-300", else: "bg-red-900 text-red-300")}>
                  <%= node_data.status %>
                </span>
              </div>
              <dl class="space-y-1 text-sm">
                <div class="flex justify-between">
                  <dt class="text-zinc-400">Latency</dt>
                  <dd><%= node_data.latency_ms || "N/A" %> ms</dd>
                </div>
                <div class="flex justify-between">
                  <dt class="text-zinc-400">Processes</dt>
                  <dd><%= node_data.process_count || "N/A" %></dd>
                </div>
                <%= if node_data.memory do %>
                  <div class="flex justify-between">
                    <dt class="text-zinc-400">Memory</dt>
                    <dd><%= format_bytes(node_data.memory[:total_memory]) %></dd>
                  </div>
                <% end %>
              </dl>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Process Distribution -->
      <div class="mb-8">
        <h2 class="text-xl font-semibold mb-4">Process Distribution</h2>
        <div class="bg-zinc-900 rounded-lg p-4">
          <div id="process-chart" class="w-full" style="height: 300px;"
               phx-hook="ProcessDistribution"
               data-processes={Jason.encode!(@processes[:nodes] || [])}>
          </div>
        </div>
      </div>

      <!-- LiveView Message Flow -->
      <div class="mb-8">
        <h2 class="text-xl font-semibold mb-4">LiveView Message Flow</h2>
        <div class="bg-zinc-900 rounded-lg p-4">
          <div id="flow-chart" class="w-full" style="height: 300px;"
               phx-hook="MessageFlow"
               data-flows={Jason.encode!(@flow[:flows] || [])}>
          </div>
        </div>
      </div>
    </div>

    <script>
      // D3.js Cluster Topology Visualization
      Hooks.ClusterTopology = {
        mounted() {
          this.drawTopology();
        },
        updated() {
          this.drawTopology();
        },
        drawTopology() {
          const el = this.el;
          const nodes = JSON.parse(el.dataset.nodes || '[]');
          const connections = JSON.parse(el.dataset.connections || '[]');

          // Clear previous;
          d3.select(el).selectAll('*').remove();

          const width = el.clientWidth;
          const height = el.clientHeight;

          const svg = d3.select(el)
            .append('svg')
            .attr('width', width)
            .attr('height', height);

          // Draw connections;
          connections.forEach(([n1, n2]) => {
            const source = nodes.find(n => n.node === n1) || {};
            const target = nodes.find(n => n.node === n2) || {};
            // Simplified line drawing;
          });

          // Draw nodes;
          nodes.forEach((node, i) => {
            const x = (width / (nodes.length + 1)) * (i + 1);
            const y = height / 2;

            svg.append('circle')
              .attr('cx', x)
              .attr('cy', y)
              .attr('r', 30)
              .attr('fill', node.status === 'alive' ? '#22c55e' : '#ef4444');

            svg.append('text')
              .attr('x', x)
              .attr('y', y + 45)
              .attr('text-anchor', 'middle')
              .attr('fill', '#e4e4e7')
              .text(node.node || 'unknown');
          });
        }
      };

      // Process Distribution Chart
      Hooks.ProcessDistribution = {
        mounted() { this.drawChart(); },
        updated() { this.drawChart(); },
        drawChart() {
          const el = this.el;
          const data = JSON.parse(el.dataset.processes || '[]');

          d3.select(el).selectAll('*').remove();

          const width = el.clientWidth;
          const height = el.clientHeight;

          const svg = d3.select(el)
            .append('svg')
            .attr('width', width)
            .attr('height', height);

          // Simple bar chart for process counts;
          const barWidth = width / (data.length || 1);

          data.forEach((d, i) => {
            const tree = d.tree || {};
            const processCount = (tree.children || []).length;

            svg.append('rect')
              .attr('x', i * barWidth + 10)
              .attr('y', height - processCount * 10)
              .attr('width', barWidth - 20)
              .attr('height', processCount * 10)
              .attr('fill', '#3b82f6');

            svg.append('text')
              .attr('x', i * barWidth + barWidth / 2)
              .attr('y', height - 5)
              .attr('text-anchor', 'middle')
              .attr('fill', '#e4e4e7')
              .text(d.node || '');
          });
        }
      };

      // Message Flow Diagram
      Hooks.MessageFlow = {
        mounted() { this.drawFlow(); },
        updated() { this.drawFlow(); },
        drawFlow() {
          const el = this.el;
          const flows = JSON.parse(el.dataset.flows || '[]');

          d3.select(el).selectAll('*').remove();

          const svg = d3.select(el)
            .append('svg')
            .attr('width', el.clientWidth)
            .attr('height', el.clientHeight);

          svg.append('text')
            .attr('x', el.clientWidth / 2)
            .attr('y', el.clientHeight / 2)
            .attr('text-anchor', 'middle')
            .attr('fill', '#e4e4e7')
            .text(flows.length > 0 ? 'Message flow data available' : 'No message flow data yet');
        }
      };
    </script>
    """
  end

  defp fetch_all(socket) do
    socket
    |> fetch_topology()
    |> fetch_health()
    |> fetch_processes()
    |> fetch_flow()
  end

  defp fetch_topology(socket) do
    case ClusterViz.topology() do
      {:ok, data} -> assign(socket, :topology, data)
      {:error, reason} -> assign(socket, :error, "Topology: #{reason}")
    end
  end

  defp fetch_health(socket) do
    case ClusterViz.health_dashboard() do
      {:ok, data} -> assign(socket, :health, data)
      {:error, reason} -> assign(socket, :error, "Health: #{reason}")
    end
  end

  defp fetch_processes(socket) do
    case ClusterViz.process_distribution() do
      {:ok, data} -> assign(socket, :processes, data)
      {:error, reason} -> assign(socket, :error, "Processes: #{reason}")
    end
  end

  defp fetch_flow(socket) do
    case ClusterViz.liveview_flow() do
      {:ok, data} -> assign(socket, :flow, data)
      _ -> assign(socket, :error, "Flow: unknown error")
    end
  end

  defp format_bytes(nil), do: "N/A"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
end
