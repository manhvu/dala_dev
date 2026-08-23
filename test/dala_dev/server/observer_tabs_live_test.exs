defmodule DalaDev.Server.ObserverTabsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint DalaDev.Server.Endpoint

  # The observer tab LiveViews share identical mount/params/event wiring;
  # each route must mount, fetch local data, and show its titled heading.
  @tabs [
    {"system", "System Info"},
    {"load", "System Load"},
    {"modules", "Modules"},
    {"ports", "Ports"},
    {"tracing", "Tracing"},
    {"applications", "Applications"}
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

  # Atom.to_string (not inspect) — dotted node names would otherwise be
  # inspected as :"name@127.0.0.1", leaving quote characters in the URL param.
  defp node_param, do: Atom.to_string(Node.self())

  describe "mount/3" do
    test "each tab mounts, fetches local data, and shows its heading without error", %{
      conn: conn
    } do
      for {tab, title} <- @tabs do
        {:ok, view, _html} = live(conn, "/observer/#{node_param()}/#{tab}")

        assert has_element?(view, "h1", "#{title}:"),
               "expected #{title} heading on the #{tab} tab"

        assert has_element?(view, "button", "Refresh"), "on the #{tab} tab"
        refute has_element?(view, ".text-red-400"), "on the #{tab} tab"

        # back-link to the observer dashboard points at this node
        assert has_element?(view, "a[href='/observer/#{node_param()}']"), "on the #{tab} tab"
      end
    end

    test "the system tab renders fetched system information", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer/#{node_param()}/system")

      assert has_element?(view, "dt", "System Version")
      assert has_element?(view, "dt", "Uptime")
      assert has_element?(view, "dt", "Process Count")

      # the fetch resolved real values rather than falling back to N/A
      refute render(view) =~ "N/A"
    end
  end

  describe "handle_event/3" do
    test "\"refresh\" refetches without surfacing an error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer/#{node_param()}/system")

      view |> element("button", "Refresh") |> render_click()

      refute has_element?(view, ".text-red-400")
      assert has_element?(view, "dt", "Process Count")
    end

    # NOTE: the select option values are rendered via inspect/1, which the
    # handler cannot parse back for dotted node names; drive the plain string.
    test "\"select_node\" with the local node name switches nodes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer/#{node_param()}/system")

      html =
        view |> element("select") |> render_change(%{"node" => Atom.to_string(Node.self())})

      refute html =~ "Invalid node"
      assert has_element?(view, "h1", Atom.to_string(Node.self()))
    end

    test "\"select_node\" with an unknown node sets an error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer/#{node_param()}/system")

      view |> element("select") |> render_change(%{"node" => "nope_xyz"})

      assert has_element?(view, ".text-red-400", "Invalid node")
    end
  end

  describe "handle_params/3" do
    test "unknown node sets an error instead of crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer/no_such_node_xyz/system")

      assert has_element?(view, ".text-red-400", "Invalid node name")
    end
  end
end
