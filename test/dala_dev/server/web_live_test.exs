defmodule DalaDev.Server.WebLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint DalaDev.Server.Endpoint

  defmodule StubDevicePoller do
    use GenServer

    # Stand-in for DalaDev.Server.DevicePoller; the "/dashboard" shortcut route
    # mounts DashboardLive, whose mount queries the poller for devices.
    def start_link(_arg),
      do: GenServer.start_link(__MODULE__, [], name: DalaDev.Server.DevicePoller)

    @impl GenServer
    def init(devices), do: {:ok, devices}

    @impl GenServer
    def handle_call(:get_devices, _from, devices), do: {:reply, devices, devices}

    @impl GenServer
    def handle_info(_msg, devices), do: {:noreply, devices}
  end

  # Every declared feature with its user-visible nav label, page heading, and a
  # marker from the feature's rendered content.
  @features [
    {"/dashboard", "Dashboard", "Activity feed coming soon"},
    {"/devices", "Devices", "Device Management"},
    {"/deploy", "Deploy", "Deploy Applications"},
    {"/emulators", "Emulators", "Emulator Management"},
    {"/observer", "Observer", "Open Full Observer"},
    {"/provision", "Provision", "Code signing and provisioning profile management"},
    {"/release", "Release", "Build and manage releases"},
    {"/profiling", "Profiling", "Performance profiling and analysis tools"},
    {"/ci", "CI Testing", "Continuous integration test management"},
    {"/logs", "Logs", "Centralized log viewing and filtering"},
    {"/settings", "Settings", "Configuration and preferences"}
  ]

  setup_all do
    case start_supervised({Phoenix.PubSub, name: DalaDev.PubSub}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    start_supervised!(DalaDev.Server.LogBuffer)
    start_supervised!(DalaDev.Server.ElixirLogBuffer)
    start_supervised!(DalaDev.Server.WatchWorker)
    start_supervised!(StubDevicePoller)

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

  defp assert_feature_active(view, name) do
    # the matching sidebar entry carries the active class
    assert has_element?(view, ".dala-nav-item.active .dala-nav-text", name)
    # the content header shows the feature's page title
    assert has_element?(view, ".dala-content-header h2", name)
  end

  defp assert_content(view, marker) do
    assert render(element(view, ".dala-content-body")) =~ marker
  end

  # ── Tests ────────────────────────────────────────────────────────────────────

  describe "mount/3" do
    test "defaults to the dashboard feature", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/web")

      assert_feature_active(view, "Dashboard")
      assert_content(view, "Activity feed coming soon")
    end

    test "offers all 11 features in the sidebar navigation", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/web")

      sidebar_html = render(element(view, ".dala-sidebar"))

      nav_count =
        sidebar_html |> String.split(~S(class="dala-nav-item)) |> length() |> Kernel.-(1)

      assert nav_count == length(@features)

      for {_path, name, _marker} <- @features do
        assert sidebar_html =~ name
      end
    end

    test "reflects the local distribution status", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/web")

      expected = if Node.alive?(), do: "Node Connected", else: "Local Mode"
      assert has_element?(view, ".dala-connection-status span:last-child", expected)
    end
  end

  describe "handle_params/3 with a feature param" do
    test "every known feature becomes active with its title and content", %{conn: conn} do
      for {path, name, marker} <- @features do
        {:ok, view, _html} = live(conn, "/web#{path}")

        assert_feature_active(view, name)
        assert_content(view, marker)
      end
    end

    test "unknown feature keeps the dashboard state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/web/bogus_feature_xyz")

      assert_feature_active(view, "Dashboard")
      assert_content(view, "Activity feed coming soon")
    end
  end

  describe "handle_params/3 path-based fallback" do
    # The 9 WebLive shortcut routes ("/dashboard" and "/observer" route to
    # other LiveViews); these carry no params, so handle_params maps the URI
    # path itself.
    @shortcut_features Enum.reject(@features, fn {path, _, _} ->
                         path in ["/dashboard", "/observer"]
                       end)

    test "shortcut paths without a param map to their feature", %{conn: conn} do
      for {path, name, marker} <- @shortcut_features do
        {:ok, view, _html} = live(conn, path)

        assert_feature_active(view, name)
        assert_content(view, marker)
      end
    end

    test "unmapped paths fall back to the dashboard", %{conn: conn} do
      # "/web" itself has no mapped path segment; it exercises the fallback arm
      {:ok, view, _html} = live(conn, "/web")

      assert_feature_active(view, "Dashboard")
    end
  end
end
