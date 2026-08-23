defmodule DalaDev.Server.LiveViewTest do
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

    Application.put_env(:dala_dev, DalaDev.Server.Endpoint,
      server: false,
      live_view: [signing_salt: "dala_dev"],
      secret_key_base: String.duplicate("a", 64),
      render_errors: [view: DalaDev.ErrorView, accepts: ~w(html)]
    )

    # Compile the LiveView templates
    Code.ensure_loaded!(DalaDev.Server.Layouts)
    Code.ensure_loaded!(DalaDev.ErrorView)

    # Endpoint must be initialized for Phoenix.ConnTest dispatch to work
    start_supervised!(DalaDev.Server.Endpoint)
    start_supervised!(DalaDev.Server.DevicePoller)
    start_supervised!(DalaDev.Server.WatchWorker)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  test "dashboard live mounts", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ "Dala"
    assert is_pid(view.pid)
  end

  test "error view renders 404" do
    rendered = DalaDev.ErrorView.render("404.html", %{})
    html = IO.iodata_to_binary(rendered.static)
    assert html =~ "404"
  end
end
