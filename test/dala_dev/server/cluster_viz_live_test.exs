defmodule DalaDev.Server.ClusterVizLiveTest do
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

  defp eventually(fun, tries \\ 100)

  defp eventually(_fun, 0), do: flunk("condition not met")

  defp eventually(fun, tries) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      eventually(fun, tries - 1)
    end
  end

  test "mount/3 renders topology, health, process, and flow sections without error", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/cluster")

    assert has_element?(view, "#topology-chart")
    assert has_element?(view, "#process-chart")
    assert has_element?(view, "#flow-chart")
    assert has_element?(view, "h2", "Cluster Topology")
    assert has_element?(view, "h2", "Node Health")
    assert has_element?(view, "h2", "Process Distribution")

    # the local node shows up in the health dashboard
    assert has_element?(view, "h3", Atom.to_string(Node.self()))

    refute has_element?(view, ".text-red-400")
  end

  test "\"refresh\" button refetches without surfacing an error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cluster")

    view |> element("button", "Refresh") |> render_click()

    html = render(view)
    assert has_element?(view, "#topology-chart")
    refute html =~ "Topology:"
    refute html =~ "Health:"
    refute has_element?(view, ".text-red-400")
  end

  test "handle_info(:refresh) refetches without error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cluster")

    send(view.pid, :refresh)

    eventually(fn ->
      html = render(view)
      html =~ "Cluster Topology" and not (html =~ "Topology:")
    end)

    refute has_element?(view, ".text-red-400")
  end
end
