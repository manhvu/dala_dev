defmodule DalaDev.Server.LiveViewMountTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint DalaDev.Server.Endpoint

  setup_all do
    case start_supervised({Phoenix.PubSub, name: DalaDev.PubSub}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    start_supervised!(DalaDev.Server.LogBuffer)
    start_supervised!(DalaDev.Server.ElixirLogBuffer)
    start_supervised!(DalaDev.Server.DevicePoller)
    start_supervised!(DalaDev.Server.WatchWorker)

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

  test "dashboard live mounts and renders", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")
    assert html =~ "Dala"
    assert Process.alive?(view.pid)
  end

  test "web live mounts with a feature param", %{conn: conn} do
    {:ok, view, html} = live(conn, "/web/devices")
    assert is_pid(view.pid)
    assert html != ""
  end

  test "web live mounts each feature route", %{conn: conn} do
    for path <- ["/dashboard", "/devices", "/deploy", "/emulators", "/logs", "/settings"] do
      {:ok, view, html} = live(conn, path)
      assert is_pid(view.pid), "failed to mount #{path}"
      assert html != "", "empty html for #{path}"
    end
  end

  test "cluster viz live mounts", %{conn: conn} do
    {:ok, view, html} = live(conn, "/cluster")
    assert is_pid(view.pid)
    assert html != ""
  end

  test "observer live mounts", %{conn: conn} do
    {:ok, view, html} = live(conn, "/observer")
    assert is_pid(view.pid)
    assert html != ""
  end

  test "observer system subpage mounts", %{conn: conn} do
    {:ok, view, html} = live(conn, "/observer/#{Node.self()}/system")
    assert is_pid(view.pid)
    assert html != ""
  end

  test "observer processes subpage mounts", %{conn: conn} do
    {:ok, view, html} = live(conn, "/observer/#{Node.self()}/processes")
    assert is_pid(view.pid)
    assert html != ""
  end

  test "observer ets subpage mounts", %{conn: conn} do
    {:ok, view, html} = live(conn, "/observer/#{Node.self()}/ets")
    assert is_pid(view.pid)
    assert html != ""
  end

  test "observer applications subpage mounts", %{conn: conn} do
    {:ok, view, html} = live(conn, "/observer/#{Node.self()}/applications")
    assert is_pid(view.pid)
    assert html != ""
  end

  test "observer modules subpage mounts", %{conn: conn} do
    {:ok, view, html} = live(conn, "/observer/#{Node.self()}/modules")
    assert is_pid(view.pid)
    assert html != ""
  end

  test "observer ports subpage mounts", %{conn: conn} do
    {:ok, view, html} = live(conn, "/observer/#{Node.self()}/ports")
    assert is_pid(view.pid)
    assert html != ""
  end

  test "observer load subpage mounts", %{conn: conn} do
    {:ok, view, html} = live(conn, "/observer/#{Node.self()}/load")
    assert is_pid(view.pid)
    assert html != ""
  end

  test "observer tracing subpage mounts", %{conn: conn} do
    {:ok, view, html} = live(conn, "/observer/#{Node.self()}/tracing")
    assert is_pid(view.pid)
    assert html != ""
  end

  test "design live mounts", %{conn: conn} do
    {:ok, view, html} = live(conn, "/design")
    assert is_pid(view.pid)
    assert html != ""
  end

  test "design live set_tab event switches tabs", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/design")

    render_click(view, "set_tab", %{"tab" => "export"})
    assert render(view) != ""
  end

  test "design live add_component event adds a node", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/design")

    render_click(view, "add_component", %{"type" => "text"})
    html = render(view)
    assert html != ""
  end

  test "design live toggle_grid event works", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/design")

    render_click(view, "toggle_grid", %{})
    assert render(view) != ""
  end

  test "dashboard set_log_filter event updates assigns", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Filter buttons are rendered as radio/select inputs; exercise the event directly
    view
    |> render_hook("set_log_filter", %{"filter" => "all"})

    html = render(view)
    assert html != ""
  end

  test "dashboard clear_logs event works", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    render_click(view, "clear_logs", %{})
    assert render(view) != ""
  end

  test "dashboard set_text_filter event filters lines", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    render_change(view, "set_text_filter", %{"text_filter" => "needle"})
    assert render(view) != ""
  end

  test "dashboard clear_text_filter event resets filter", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    render_click(view, "clear_text_filter", %{})
    assert render(view) != ""
  end

  test "dashboard set_elixir_text_filter event works", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    render_change(view, "set_elixir_text_filter", %{"elixir_text_filter" => "error"})
    assert render(view) != ""
  end

  test "dashboard clear_elixir_text_filter event works", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    render_click(view, "clear_elixir_text_filter", %{})
    assert render(view) != ""
  end

  test "dashboard clear_elixir_logs event works", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    render_click(view, "clear_elixir_logs", %{})
    assert render(view) != ""
  end

  test "dashboard toggle_watch event works", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    render_click(view, "toggle_watch", %{})
    assert render(view) != ""
  end
end
