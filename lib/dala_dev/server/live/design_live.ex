defmodule DalaDev.Server.DesignLive do
  use Phoenix.LiveView

  @grid_size 20
  @default_zoom 100

  @impl true
  @spec mount(term(), term(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    design = %{
      nodes: []
    }

    component_types = [
      %{type: :column, name: "Column", icon: "☰", category: "Layout"},
      %{type: :row, name: "Row", icon: "☱", category: "Layout"},
      %{type: :box, name: "Box", icon: "□", category: "Layout"},
      %{type: :text, name: "Text", icon: "T", category: "Content"},
      %{type: :button, name: "Button", icon: "▣", category: "Content"},
      %{type: :icon, name: "Icon", icon: "★", category: "Content"},
      %{type: :image, name: "Image", icon: "🖼", category: "Content"},
      %{type: :divider, name: "Divider", icon: "─", category: "Content"},
      %{type: :spacer, name: "Spacer", icon: "◇", category: "Content"},
      %{type: :text_field, name: "Text Field", icon: "▭", category: "Input"},
      %{type: :toggle, name: "Toggle", icon: "⊘", category: "Input"},
      %{type: :slider, name: "Slider", icon: "◫", category: "Input"},
      %{type: :switch, name: "Switch", icon: "⇄", category: "Input"},
      %{type: :progress, name: "Progress", icon: "▰", category: "Feedback"},
      %{type: :activity_indicator, name: "Activity", icon: "◌", category: "Feedback"},
      %{type: :tab_bar, name: "Tab Bar", icon: "▤", category: "Navigation"},
      %{type: :scroll, name: "Scroll", icon: "↕", category: "Navigation"},
      %{type: :modal, name: "Modal", icon: "⏏", category: "Overlay"},
      %{type: :safe_area, name: "Safe Area", icon: "⊡", category: "System"},
      %{type: :status_bar, name: "Status Bar", icon: "▤", category: "System"},
      %{type: :list, name: "List", icon: "☰", category: "Content"},
      %{type: :webview, name: "WebView", icon: "◉", category: "Media"},
      %{type: :camera_preview, name: "Camera", icon: "☐", category: "Media"},
      %{type: :video, name: "Video", icon: "▶", category: "Media"}
    ]

    socket =
      socket
      |> assign(:design, design)
      |> assign(:component_types, component_types)
      |> assign(:selected_node, nil)
      |> assign(:grid_visible, true)
      |> assign(:snap_to_grid, true)
      |> assign(:zoom, @default_zoom)
      |> assign(:grid_size, @grid_size)
      |> assign(:active_tab, "components")
      |> assign(:export_format, "dsl")
      |> assign(:generated_code, "")

    {:ok, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_event("add_component", %{"type" => type_str}, socket) do
    type = String.to_atom(type_str)
    design = socket.assigns.design

    new_node = %{
      id: generate_id(),
      type: type,
      name: Atom.to_string(type) |> String.replace("_", " ") |> String.capitalize(),
      x: 100,
      y: 100,
      props: default_props(type),
      children: []
    }

    design = %{design | nodes: design.nodes ++ [new_node]}
    socket = assign(socket, :design, design)
    socket = assign(socket, :generated_code, generate_code(design, socket.assigns.export_format))
    {:noreply, socket}
  end

  def handle_event("select_node", %{"id" => node_id}, socket) do
    socket = assign(socket, :selected_node, node_id)
    {:noreply, socket}
  end

  def handle_event(
        "update_property",
        %{"node_id" => node_id, "key" => key, "value" => value},
        socket
      ) do
    design = socket.assigns.design

    nodes =
      Enum.map(design.nodes, fn node ->
        if node.id == node_id do
          props = Map.put(node.props, key, value)
          %{node | props: props}
        else
          node
        end
      end)

    design = %{design | nodes: nodes}
    socket = assign(socket, :design, design)
    socket = assign(socket, :generated_code, generate_code(design, socket.assigns.export_format))
    {:noreply, socket}
  end

  def handle_event("delete_node", %{"id" => node_id}, socket) do
    design = socket.assigns.design
    nodes = Enum.reject(design.nodes, &(&1.id == node_id))
    design = %{design | nodes: nodes}
    socket = assign(socket, :design, design)
    socket = assign(socket, :selected_node, nil)
    socket = assign(socket, :generated_code, generate_code(design, socket.assigns.export_format))
    {:noreply, socket}
  end

  def handle_event("move_node", %{"id" => node_id, "x" => x, "y" => y}, socket) do
    design = socket.assigns.design

    nodes =
      Enum.map(design.nodes, fn node ->
        if node.id == node_id do
          %{node | x: String.to_integer(x), y: String.to_integer(y)}
        else
          node
        end
      end)

    design = %{design | nodes: nodes}
    socket = assign(socket, :design, design)
    {:noreply, socket}
  end

  def handle_event("clear_canvas", _params, socket) do
    design = %{nodes: []}
    socket = assign(socket, :design, design)
    socket = assign(socket, :selected_node, nil)
    socket = assign(socket, :generated_code, "")
    {:noreply, socket}
  end

  def handle_event("toggle_grid", _params, socket) do
    socket = assign(socket, :grid_visible, !socket.assigns.grid_visible)
    {:noreply, socket}
  end

  def handle_event("toggle_snap", _params, socket) do
    socket = assign(socket, :snap_to_grid, !socket.assigns.snap_to_grid)
    {:noreply, socket}
  end

  def handle_event("set_zoom", %{"zoom" => zoom}, socket) do
    socket = assign(socket, :zoom, String.to_integer(zoom))
    {:noreply, socket}
  end

  def handle_event("set_export_format", %{"format" => format}, socket) do
    socket = assign(socket, :export_format, format)
    socket = assign(socket, :generated_code, generate_code(socket.assigns.design, format))
    {:noreply, socket}
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode64()
    |> String.replace(DalaDev.Utils.compile_regex("[^A-Za-z0-9]"), "")
    |> String.slice(0, 8)
  end

  defp default_props(:column), do: %{"direction" => "vertical", "spacing" => "10"}
  defp default_props(:row), do: %{"direction" => "horizontal", "spacing" => "10"}
  defp default_props(:box), do: %{"width" => "100", "height" => "100", "color" => "#ffffff"}
  defp default_props(:text), do: %{"text" => "Text", "size" => "16", "color" => "#000000"}
  defp default_props(:button), do: %{"text" => "Button", "action" => ""}
  defp default_props(:icon), do: %{"name" => "star", "size" => "24"}
  defp default_props(:image), do: %{"src" => "", "width" => "100", "height" => "100"}
  defp default_props(:divider), do: %{"orientation" => "horizontal"}
  defp default_props(:spacer), do: %{"height" => "20"}
  defp default_props(:text_field), do: %{"placeholder" => "Enter text", "value" => ""}
  defp default_props(:toggle), do: %{"value" => "false"}
  defp default_props(:slider), do: %{"min" => "0", "max" => "100", "value" => "50"}
  defp default_props(:progress), do: %{"value" => "50", "max" => "100"}
  defp default_props(:activity_indicator), do: %{}
  defp default_props(:tab_bar), do: %{"tabs" => "Tab 1,Tab 2,Tab 3"}
  defp default_props(:scroll), do: %{"direction" => "vertical"}
  defp default_props(:modal), do: %{"title" => "Modal"}
  defp default_props(:safe_area), do: %{}
  defp default_props(:status_bar), do: %{"style" => "default"}
  defp default_props(:list), do: %{"items" => "Item 1,Item 2,Item 3"}
  defp default_props(:webview), do: %{"url" => "https://example.com"}
  defp default_props(:camera_preview), do: %{}
  defp default_props(:video), do: %{"src" => ""}
  defp default_props(:native_view), do: %{"component" => ""}
  defp default_props(:switch), do: %{"value" => "false"}
  defp default_props(_), do: %{}

  defp generate_code(design, format) do
    case format do
      "dsl" -> generate_dsl_code(design.nodes)
      "map" -> generate_map_code(design.nodes)
      _ -> generate_dsl_code(design.nodes)
    end
  end

  defp generate_dsl_code(nodes) do
    nodes_to_dsl(nodes)
  end

  defp generate_map_code(nodes) do
    nodes_to_map(nodes)
  end

  defp nodes_to_dsl(nodes) do
    nodes
    |> Enum.map(&node_to_dsl/1)
    |> Enum.join("\n")
  end

  defp node_to_dsl(%{type: type, props: props, children: children}) do
    props_str = props_to_dsl(props)

    children_str =
      if children && children != [] do
        children
        |> Enum.map(&node_to_dsl/1)
        |> Enum.join("\n  ")
        |> (fn s -> " do\n  " <> s <> "\nend" end).()
      else
        ""
      end

    "#{type}(#{props_str})#{children_str}"
  end

  defp props_to_dsl(props) do
    props
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join(", ")
  end

  defp nodes_to_map(nodes) do
    nodes
    |> Enum.map(&node_to_map/1)
    |> inspect(pretty: true)
  end

  defp node_to_map(%{type: type, props: props, children: children}) do
    %{
      type: type,
      props: props,
      children: children
    }
  end

  defp preview_node(%{type: :text, props: props}) do
    text = Map.get(props, "text", "Text")
    "<span class='preview-text'>#{text}</span>"
  end

  defp preview_node(%{type: :button, props: props}) do
    text = Map.get(props, "text", "Button")
    "<button class='preview-button'>#{text}</button>"
  end

  defp preview_node(%{type: :text_field, props: props}) do
    placeholder = Map.get(props, "placeholder", "Input")
    "<input class='preview-input' placeholder='#{placeholder}' />"
  end

  defp preview_node(%{type: :toggle}), do: "<div class='preview-toggle'>Toggle</div>"
  defp preview_node(%{type: :slider}), do: "<div class='preview-slider'>◽◽◽</div>"
  defp preview_node(%{type: :image}), do: "<div class='preview-image'>🖼️</div>"
  defp preview_node(%{type: :divider}), do: "<hr class='preview-divider' />"
  defp preview_node(%{type: :progress}), do: "<div class='preview-progress'>◽◽◽◽</div>"
  defp preview_node(%{type: :list}), do: "<div class='preview-list'>📄 📄 📄</div>"
  defp preview_node(%{type: type}), do: "<div class='preview-default'>#{type}</div>"

  defp node_icon(%{type: :column}), do: "☰"
  defp node_icon(%{type: :row}), do: "☱"
  defp node_icon(%{type: :box}), do: "□"
  defp node_icon(%{type: :text}), do: "T"
  defp node_icon(%{type: :button}), do: "▣"
  defp node_icon(%{type: :icon}), do: "★"
  defp node_icon(%{type: :image}), do: "🖼"
  defp node_icon(%{type: :divider}), do: "─"
  defp node_icon(%{type: :spacer}), do: "◇"
  defp node_icon(%{type: :text_field}), do: "▭"
  defp node_icon(%{type: :toggle}), do: "⊘"
  defp node_icon(%{type: :slider}), do: "◫"
  defp node_icon(%{type: :progress}), do: "▰"
  defp node_icon(%{type: :activity_indicator}), do: "◌"
  defp node_icon(%{type: :tab_bar}), do: "▤"
  defp node_icon(%{type: :scroll}), do: "↕"
  defp node_icon(%{type: :modal}), do: "⏏"
  defp node_icon(%{type: :safe_area}), do: "⊡"
  defp node_icon(%{type: :status_bar}), do: "▤"
  defp node_icon(%{type: :list}), do: "☰"
  defp node_icon(%{type: :webview}), do: "◉"
  defp node_icon(%{type: :camera_preview}), do: "☐"
  defp node_icon(%{type: :video}), do: "▶"
  defp node_icon(%{type: :native_view}), do: "◆"
  defp node_icon(%{type: :switch}), do: "⇄"
  defp node_icon(_), do: "?"

  @impl true
  @spec render(Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="design-container">
      <!-- Top Toolbar -->
      <div class="toolbar">
        <div class="toolbar-left">
          <h1>Dala UI Designer</h1>
        </div>
        <div class="toolbar-right">
          <button phx-click="clear_canvas" class="btn btn-danger">Clear Canvas</button>
          <button phx-click="toggle_grid" class="btn btn-secondary"><%= if @grid_visible, do: "Hide Grid", else: "Show Grid" %></button>
          <button phx-click="toggle_snap" class="btn btn-secondary"><%= if @snap_to_grid, do: "Snap: ON", else: "Snap: OFF" %></button>
          <select phx-change="set_zoom" class="zoom-select">
            <option value="50" selected={@zoom == 50}>50%</option>
            <option value="75" selected={@zoom == 75}>75%</option>
            <option value="100" selected={@zoom == 100}>100%</option>
            <option value="125" selected={@zoom == 125}>125%</option>
            <option value="150" selected={@zoom == 150}>150%</option>
          </select>
        </div>
      </div>

      <!-- Main Content -->
      <div class="main-content">
        <!-- Left Panel - Components -->
        <div class="panel components-panel">
          <div class="panel-header">
            <button phx-click="set_tab" phx-value-tab="components" class={if @active_tab == "components", do: "active"}>Components</button>
            <button phx-click="set_tab" phx-value-tab="properties" class={if @active_tab == "properties", do: "active"}>Properties</button>
            <button phx-click="set_tab" phx-value-tab="export" class={if @active_tab == "export", do: "active"}>Export</button>
          </div>

          <div class="panel-content">
            <!-- Components Tab -->
            <div class={if @active_tab == "components", do: "tab-content active", else: "tab-content"}>
              <div class="component-categories">
                <%= for category <- ["Layout", "Content", "Input", "Feedback", "Navigation", "Overlay", "System", "Media"] do %>
                  <div class="category">
                    <h4><%= category %></h4>
                    <div class="component-list">
                      <%= for comp <- @component_types, comp.category == category do %>
                        <div
                          class="component-item"
                          phx-click="add_component"
                          phx-value-type={comp.type}
                          draggable="true"
                        >
                          <span class="component-icon"><%= comp.icon %></span>
                          <span class="component-name"><%= comp.name %></span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>

            <!-- Properties Tab -->
            <div class={if @active_tab == "properties", do: "tab-content active", else: "tab-content"}>
              <%= if @selected_node do %>
                <%= for node <- @design.nodes, node.id == @selected_node do %>
                  <div class="node-properties">
                    <h4>Properties: <%= node.name %></h4>
                    <div class="property-list">
                      <div class="property-item">
                        <label>ID:</label>
                        <input type="text" value={node.id} disabled />
                      </div>
                      <div class="property-item">
                        <label>Type:</label>
                        <input type="text" value={node.type} disabled />
                      </div>
                      <%= for {key, value} <- node.props do %>
                        <div class="property-item">
                          <label><%= key %>:</label>
                          <input
                            type="text"
                            value={value}
                            phx-debounce="300"
                            phx-change="update_property"
                            phx-value-node_id={node.id}
                            phx-value-key={key}
                          />
                        </div>
                      <% end %>
                    </div>
                    <div class="property-actions">
                      <button phx-click="delete_node" phx-value-id={node.id} class="btn btn-sm btn-danger">Delete</button>
                    </div>
                  </div>
                <% end %>
              <% else %>
                <div class="no-selection">
                  <p>Select a node to edit its properties</p>
                </div>
              <% end %>
            </div>

            <!-- Export Tab -->
            <div class={if @active_tab == "export", do: "tab-content active", else: "tab-content"}>
              <div class="export-options">
                <h4>Export Format</h4>
                <div class="format-selector">
                  <label>
                    <input type="radio" name="format" value="dsl" checked={@export_format == "dsl"} phx-change="set_export_format" phx-value-format="dsl" />
                    DSL (Spark)
                  </label>
                  <label>
                    <input type="radio" name="format" value="map" checked={@export_format == "map"} phx-change="set_export_format" phx-value-format="map" />
                    Map Format
                  </label>
                </div>
              </div>
              <div class="generated-code">
                <pre><code><%= @generated_code %></code></pre>
              </div>
            </div>
          </div>
        </div>

        <!-- Center Canvas -->
        <div class="canvas-container">
          <div
            class="canvas"
            id="design-canvas"
            phx-hook="DesignCanvas"
            data-zoom={@zoom}
            data-grid-visible={@grid_visible}
            data-snap-to-grid={@snap_to_grid}
            data-grid-size={@grid_size}
          >
            <!-- Grid Background -->
            <%= if @grid_visible do %>
              <div class="grid-background" style={"background-size: #{@grid_size}px #{@grid_size}px;"}></div>
            <% end %>

            <!-- Canvas Content -->
            <div class="canvas-content" style={"transform: scale(#{@zoom / 100});"}>
              <%= for node <- @design.nodes do %>
                <div
                  class={"canvas-node #{if node.id == @selected_node, do: "selected"}"}
                  id={"node-#{node.id}"}
                  data-id={node.id}
                  style={"left: #{node.x}px; top: #{node.y}px;"}
                  phx-click="select_node"
                  phx-value-id={node.id}
                >
                  <div class="node-visual #{node.type}">
                    <%= node_icon(node) %>
                    <span class="node-label"><%= node.name %></span>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Right Panel - Preview -->
        <div class="panel preview-panel">
          <div class="panel-header">
            <h3>Preview</h3>
          </div>
          <div class="panel-content preview-content">
            <div class="preview-canvas">
              <%= for node <- @design.nodes |> Enum.sort_by(&{&1.y, &1.x}) do %>
                <div class="preview-node #{node.type}">
                  <%= Phoenix.HTML.raw(preview_node(node)) %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
