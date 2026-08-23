defmodule DalaDev.Server.DesignLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint DalaDev.Server.Endpoint

  # The component types exposed in the palette (mirrors DesignLive's list);
  # each is user-visible as a `.component-item` entry.
  @component_types [
    :column,
    :row,
    :box,
    :text,
    :button,
    :icon,
    :image,
    :divider,
    :spacer,
    :text_field,
    :toggle,
    :slider,
    :switch,
    :progress,
    :activity_indicator,
    :tab_bar,
    :scroll,
    :modal,
    :safe_area,
    :status_bar,
    :list,
    :webview,
    :camera_preview,
    :video
  ]

  setup_all do
    case start_supervised({Phoenix.PubSub, name: DalaDev.PubSub}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Application.put_env(:dala_dev, DalaDev.Server.Endpoint,
      server: false,
      live_view: [signing_salt: "dala_dev"],
      secret_key_base: String.duplicate("a", 64),
      render_errors: [view: DalaDev.ErrorView, accepts: ~w(html)],
      pubsub_server: DalaDev.PubSub,
      url: [host: "localhost"],
      render_on_error: false
    )

    start_supervised!(DalaDev.Server.Endpoint)

    {:ok, conn: build_conn()}
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp occurrences(html, needle), do: html |> String.split(needle) |> length() |> Kernel.-(1)

  defp add_node(view, type),
    do: render_click(view, "add_component", %{"type" => Atom.to_string(type)})

  # Canvas node names derive from the type the same way the LiveView derives them.
  defp expected_label(type),
    do: type |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp canvas_html(view), do: render(element(view, ".canvas-content"))

  defp node_count(view), do: occurrences(canvas_html(view), ~S(class="canvas-node))

  defp node_ids(view) do
    Regex.scan(Regex.compile!("id=\"node-([A-Za-z0-9]+)\""), canvas_html(view),
      capture: :all_but_first
    )
    |> List.flatten()
  end

  defp node_label(view) do
    [label] =
      Regex.run(Regex.compile!(~S{class="node-label">([^<]+)<}), canvas_html(view),
        capture: :all_but_first
      )

    label
  end

  defp generated_code(view) do
    html = render(element(view, ".generated-code code"))

    case Regex.run(Regex.compile!("^<code>(.*)</code>$", "s"), html, capture: :all_but_first) do
      [inner] -> inner
      _ -> html
    end
  end

  defp no_selection_visible?(view),
    do: has_element?(view, ".no-selection p", "Select a node to edit its properties")

  # ── Tests ────────────────────────────────────────────────────────────────────

  describe "mount/3" do
    test "starts with an empty canvas and default tool state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/design")

      assert node_count(view) == 0

      # all 24 palette components are offered
      palette_html = render(element(view, ".components-panel"))
      assert occurrences(palette_html, ~S(class="component-item")) == 24

      assert no_selection_visible?(view)

      # grid visible by default
      assert has_element?(view, ".grid-background")
      assert has_element?(view, "button", "Hide Grid")

      # snap-to-grid enabled by default
      assert has_element?(view, "button", "Snap: ON")

      # default zoom of 100% is the selected option
      assert has_element?(view, ~S(.zoom-select option[value="100"][selected]))

      # the components tab is active
      assert render(element(view, ".tab-content.active")) =~ "Layout"
      assert has_element?(view, ".panel-header button.active", "Components")

      # DSL export format is pre-selected
      assert has_element?(view, ~S(.format-selector input[name="format"][value="dsl"][checked]))

      # nothing has been generated yet
      assert generated_code(view) |> String.trim() == ""
    end
  end

  describe "\"add_component\"" do
    test "appends a positioned Text node and generates DSL code", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/design")

      add_node(view, :text)

      assert node_count(view) == 1
      assert node_label(view) == "Text"

      # NOTE: the preview pane currently renders escaped markup (preview_node/1
      # output is HTML-escaped by the template), so we assert on its content
      # marker rather than on preview elements.
      assert render(element(view, ".preview-panel")) =~ "preview-text"

      # new nodes land at the default position
      node_html = render(element(view, ".canvas-node"))
      assert node_html =~ "left: 100px; top: 100px;"

      code = generated_code(view)
      assert code =~ "text("
      assert code =~ "size: &quot;16&quot;"
    end

    test "each palette component type can be added without crashing", %{conn: conn} do
      for type <- @component_types do
        {:ok, view, _html} = live(conn, "/design")

        add_node(view, type)

        assert node_count(view) == 1, "expected exactly one node after adding #{type}"
        assert node_label(view) == expected_label(type)
      end
    end
  end

  describe "\"update_property\"" do
    # NOTE: selecting a node that has props currently crashes rendering
    # (`phx-target={@myself}` is invalid outside a component — KeyError on :myself),
    # so these drive update_property directly and verify through the exported code.
    test "updates props on the matching node and regenerates code", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/design")
      add_node(view, :text)
      [id] = node_ids(view)

      render_click(view, "update_property", %{
        "node_id" => id,
        "key" => "text",
        "value" => "Hello"
      })

      # the exported code reflects the new value alongside the untouched props
      code = generated_code(view)
      assert code =~ "Hello"
      assert code =~ "size: &quot;16&quot;"
    end

    test "unknown node id leaves the design untouched", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/design")
      add_node(view, :box)
      code_before = generated_code(view)

      render_click(view, "update_property", %{
        "node_id" => "missing",
        "key" => "width",
        "value" => "1"
      })

      assert generated_code(view) == code_before
    end
  end

  describe "\"delete_node\"" do
    test "removes the node and clears the selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/design")
      add_node(view, :button)

      # activity_indicator has an empty prop set, so selecting it exercises the
      # property-editor branch without hitting the @myself KeyError (see above)
      add_node(view, :activity_indicator)
      [_button_id, indicator_id] = node_ids(view)

      render_click(view, "select_node", %{"id" => indicator_id})
      assert has_element?(view, ".node-properties h4", "Properties: Activity")
      refute no_selection_visible?(view)

      render_click(view, "delete_node", %{"id" => indicator_id})

      assert node_count(view) == 1
      assert node_label(view) == "Button"
      assert no_selection_visible?(view)

      code = generated_code(view)
      assert code =~ "button("
      refute code =~ "activity_indicator("
    end
  end

  describe "\"move_node\"" do
    test "parses string coordinates into integers", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/design")
      add_node(view, :box)
      [id] = node_ids(view)

      render_click(view, "move_node", %{"id" => id, "x" => "42", "y" => "7"})

      assert render(element(view, ".canvas-node")) =~ "left: 42px; top: 7px;"
    end
  end

  describe "\"clear_canvas\"" do
    test "empties nodes, selection, and generated code", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/design")
      add_node(view, :text)

      render_click(view, "clear_canvas", %{})

      assert node_count(view) == 0
      assert no_selection_visible?(view)
      assert generated_code(view) |> String.trim() == ""
    end
  end

  describe "tool toggles" do
    test "\"toggle_grid\" flips the grid visibility", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/design")

      render_click(view, "toggle_grid", %{})
      assert has_element?(view, "button", "Show Grid")
      refute has_element?(view, ".grid-background")

      render_click(view, "toggle_grid", %{})
      assert has_element?(view, "button", "Hide Grid")
      assert has_element?(view, ".grid-background")
    end

    test "\"toggle_snap\" disables snapping", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/design")

      render_click(view, "toggle_snap", %{})

      assert has_element?(view, "button", "Snap: OFF")
    end

    test "\"set_zoom\" applies the chosen zoom level", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/design")

      render_click(view, "set_zoom", %{"zoom" => "150"})

      assert has_element?(view, ~S(.zoom-select option[value="150"][selected]))
      assert render(element(view, "#design-canvas")) =~ "data-zoom=\"150\""
      assert has_element?(view, ~S{.canvas-content[style*="scale(1.5)"]})
    end

    test "\"set_export_format\" switches format and regenerates code", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/design")
      add_node(view, :button)

      render_click(view, "set_export_format", %{"format" => "map"})

      assert has_element?(view, ~S(.format-selector input[name="format"][value="map"][checked]))

      code = generated_code(view)
      assert code =~ "%{"
      assert code =~ "type: :button"
    end

    test "\"set_tab\" activates the requested tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/design")

      render_click(view, "set_tab", %{"tab" => "properties"})

      assert has_element?(view, ".panel-header button.active", "Properties")
      assert render(element(view, ".tab-content.active")) =~ "Select a node"
    end
  end

  describe "\"select_node\"" do
    test "opens the property editor for the clicked node", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/design")

      # activity_indicator has an empty prop set, so the property editor renders
      # without the @myself KeyError that prop-ful nodes currently trigger
      add_node(view, :activity_indicator)
      [id] = node_ids(view)

      render_click(view, "select_node", %{"id" => id})

      assert has_element?(view, ".node-properties h4", "Properties: Activity")
      refute no_selection_visible?(view)
    end
  end
end
