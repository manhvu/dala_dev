defmodule DalaDev.Server.DashboardLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint DalaDev.Server.Endpoint

  defmodule FakeDevicePoller do
    use GenServer

    # Stand-in for DalaDev.Server.DevicePoller so dashboard tests get a stable,
    # deterministic device list without touching adb/simctl or racing broadcasts.
    def start_link(devices) do
      GenServer.start_link(__MODULE__, devices, name: DalaDev.Server.DevicePoller)
    end

    @impl GenServer
    def init(devices), do: {:ok, devices}

    @impl GenServer
    def handle_call(:get_devices, _from, devices), do: {:reply, devices, devices}

    @impl GenServer
    def handle_info(_msg, devices), do: {:noreply, devices}
  end

  @devices [
    %{
      serial: "s1serial",
      name: "Pixel Test",
      platform: :android,
      beam_running: true,
      battery: 80,
      status: :connected
    },
    %{
      serial: "s2serial",
      name: "Sim Test",
      platform: :ios,
      beam_running: false,
      battery: nil,
      status: :connected
    }
  ]

  setup_all do
    case start_supervised({Phoenix.PubSub, name: DalaDev.PubSub}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    start_supervised!(DalaDev.Server.LogBuffer)
    start_supervised!(DalaDev.Server.ElixirLogBuffer)
    start_supervised!(DalaDev.Server.WatchWorker)
    start_supervised!({FakeDevicePoller, @devices})

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

  # Polls until the rendered HTML matches, then returns that HTML snapshot so
  # subsequent assertions are immune to later async updates.
  defp wait_for_html(view, match?, tries \\ 100)

  defp wait_for_html(_view, _match?, 0), do: flunk("expected html condition to become true")

  defp wait_for_html(view, match?, tries) do
    html = render(view)

    if match?.(html) do
      html
    else
      Process.sleep(20)
      wait_for_html(view, match?, tries - 1)
    end
  end

  defp occurrences(html, needle), do: html |> String.split(needle) |> length() |> Kernel.-(1)

  # ── Tests ────────────────────────────────────────────────────────────────────

  test "handle_info({:devices_updated, devices}) re-renders the device list", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "section", "Pixel Test")
    assert render(view) =~ "2 device(s) connected"

    send(view.pid, {:devices_updated, [device_fresh()]})

    html =
      wait_for_html(view, fn html ->
        html =~ "Fresh Device" and html =~ "1 device(s) connected"
      end)

    refute html =~ "Pixel Test"
    refute html =~ "No devices"
  end

  test "handle_info({:watch_status, status}) flips the watch button label", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "button[phx-click='toggle_watch']", "▶ Watch")

    send(view.pid, {:watch_status, :watching})

    eventually(fn ->
      has_element?(view, "button[phx-click='toggle_watch']", "⏹ Watching")
    end)

    refute has_element?(view, "button[phx-click='toggle_watch']", "▶ Watch")

    send(view.pid, {:watch_status, :stopped})

    eventually(fn ->
      has_element?(view, "button[phx-click='toggle_watch']", "▶ Watch") and
        not has_element?(view, "button", "Watching")
    end)
  end

  test "handle_info({:deploy_line, serial, line}) routes output under the right device card", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "section", "Pixel Test")

    send(view.pid, {:deploy_line, "s1serial", "BUILD OUTPUT FOR S1"})
    eventually(fn -> render(view) =~ "BUILD OUTPUT FOR S1" end)

    send(view.pid, {:deploy_line, "s2serial", "BUILD OUTPUT FOR S2"})

    html = wait_for_html(view, &String.contains?(&1, "BUILD OUTPUT FOR S2"))

    # each line renders exactly once — i.e. under its own serial's card only
    assert occurrences(html, "BUILD OUTPUT FOR S1") == 1
    assert occurrences(html, "BUILD OUTPUT FOR S2") == 1
  end

  test "deploy completes: buttons disable while running and re-enable after deploy_done", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/")

    # spawn_deploy resolves `mix` via PATH and shells out; point PATH at a shim
    # that exits immediately so the whole lifecycle runs without a real deploy.
    shim_dir =
      Path.join(System.tmp_dir!(), "dala_dev_fake_mix_#{System.unique_integer([:positive])}")

    File.mkdir_p!(shim_dir)
    File.write!(Path.join(shim_dir, "mix"), "#!/bin/sh\nsleep 0.3\nexit 0\n")
    File.chmod!(Path.join(shim_dir, "mix"), 0o755)

    original_path = System.get_env("PATH")

    try do
      System.put_env("PATH", shim_dir)

      html =
        view
        |> element("button[phx-value-serial='s1serial'][phx-value-mode='update']")
        |> render_click()

      assert html =~ "Updating"
      assert html =~ "disabled"
    after
      if original_path, do: System.put_env("PATH", original_path), else: System.delete_env("PATH")
    end

    # the shim exits immediately, which triggers {:deploy_done, "s1serial"} —
    # output stays visible and the deploy buttons re-enable
    eventually(fn ->
      html = render(view)
      not (html =~ "Updating") and not (html =~ "Deploying")
    end)

    assert view
           |> element(
             "button[phx-value-serial='s1serial'][phx-value-mode='update']:not([disabled])"
           )
           |> render() =~ "Update"

    File.rm_rf!(shim_dir)
  end

  test "handle_info({:watch_push, info}) shows pushed modules and node count", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    send(view.pid, {:watch_status, :watching})

    push_info = %{
      pushed: 3,
      failed: [],
      nodes: [:a@x],
      files: ["lib/dala_dev/foo.ex"],
      at: ~T[12:34:56]
    }

    send(view.pid, {:watch_push, push_info})

    html = wait_for_html(view, &String.contains?(&1, "last push: 3 module(s)"))
    assert html =~ "1 node(s)"
    assert html =~ "12:34:56"
  end

  defp device_fresh do
    %{
      serial: "fresh1",
      name: "Fresh Device",
      platform: :android,
      beam_running: false,
      battery: nil,
      status: :connected
    }
  end
end
