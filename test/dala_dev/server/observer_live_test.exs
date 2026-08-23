defmodule DalaDev.Server.ObserverLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint DalaDev.Server.Endpoint

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

  # Atom.to_string (not inspect) — dotted node names would otherwise be
  # inspected as :"name@127.0.0.1", leaving quote characters in the URL param.
  defp node_param, do: Atom.to_string(Node.self())

  defp eventually(fun, tries \\ 100)

  defp eventually(_fun, 0), do: flunk("condition not met")

  defp eventually(fun, tries) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      eventually(fun, tries - 1)
    end
  end

  defp assert_summary_rendered(view) do
    assert has_element?(view, "dt", "Processes")
    assert has_element?(view, "dt", "ETS Tables")
    assert has_element?(view, "dt", "Memory (Total)")
    assert has_element?(view, "dt", "Uptime")
    refute has_element?(view, ".text-red-400")
  end

  # ── Tests ────────────────────────────────────────────────────────────────────

  describe "mount/3" do
    test "loads a local summary without error (params without a node are ignored)", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/observer")

      assert has_element?(view, "h1", "Observer:")
      assert has_element?(view, "h1", Atom.to_string(Node.self()))
      assert_summary_rendered(view)
      refute render(view) =~ "Loading"
      refute has_element?(view, ".text-red-400")
    end

    test "offers navigation cards for every observer subpage", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer")

      for tab <- ["system", "processes", "ets", "applications", "modules", "ports"] do
        assert has_element?(view, "a[href='/observer/#{node_param()}/#{tab}']")
      end
    end
  end

  describe "handle_params/3" do
    test "switches to the given node and refetches", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer/#{node_param()}")

      assert has_element?(view, "h1", Atom.to_string(Node.self()))
      assert_summary_rendered(view)
    end

    test "unknown node sets an error instead of crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer/no_such_node_xyz")

      assert has_element?(view, ".text-red-400", "Invalid node name")
      # note: the summary fetched at mount for the local node stays visible
    end
  end

  describe "handle_info/2" do
    test ":refresh refetches the summary", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer")

      send(view.pid, :refresh)
      eventually(fn -> has_element?(view, "dt", "Processes") end)

      assert_summary_rendered(view)
    end
  end

  describe "handle_event/3" do
    test "\"refresh\" button refetches", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer")

      view |> element("button", "Refresh") |> render_click()

      assert_summary_rendered(view)
    end

    # NOTE: the node <select> renders option values via inspect/1, which the
    # handler cannot parse back once this VM is distributed under a dotted name
    # (:"dala_dev@127.0.0.1" leaves quote chars after trimming ":"). We drive
    # the handler with the plain atom string here.
    test "\"select_node\" with the local node name switches nodes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer")

      html =
        view |> element("select") |> render_change(%{"node" => Atom.to_string(Node.self())})

      refute html =~ "Invalid node"
      assert has_element?(view, "h1", Atom.to_string(Node.self()))
    end

    test "\"select_node\" with an unknown node sets an error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer")

      view |> element("select") |> render_change(%{"node" => "nope_xyz"})

      assert has_element?(view, ".text-red-400", "Invalid node")
    end
  end
end
