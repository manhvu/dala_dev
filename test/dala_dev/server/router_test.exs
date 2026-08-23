defmodule DalaDev.Server.RouterTest do
  use ExUnit.Case, async: true

  @router DalaDev.Server.Router

  @live_paths [
    "/",
    "/web",
    "/web/devices",
    "/cluster",
    "/observer",
    "/observer/nonode@nohost",
    "/observer/nonode@nohost/system",
    "/observer/nonode@nohost/processes",
    "/observer/nonode@nohost/ets",
    "/observer/nonode@nohost/applications",
    "/observer/nonode@nohost/modules",
    "/observer/nonode@nohost/ports",
    "/observer/nonode@nohost/load",
    "/observer/nonode@nohost/tracing",
    "/design",
    "/dashboard"
  ]

  @all_live_views [
    DalaDev.Server.DashboardLive,
    DalaDev.Server.WebLive,
    DalaDev.Server.ClusterVizLive,
    DalaDev.Server.ObserverLive,
    DalaDev.Server.ObserverLive.System,
    DalaDev.Server.ObserverLive.Processes,
    DalaDev.Server.ObserverLive.ETS,
    DalaDev.Server.ObserverLive.Applications,
    DalaDev.Server.ObserverLive.Modules,
    DalaDev.Server.ObserverLive.Ports,
    DalaDev.Server.ObserverLive.Load,
    DalaDev.Server.ObserverLive.Tracing,
    DalaDev.Server.DesignLive
  ]

  defp live_view_for(path) do
    info = Phoenix.Router.route_info(@router, "GET", path, "www.example.com")

    case info do
      %{phoenix_live_view: {view, _action, _opts, _meta}} -> view
      _ -> nil
    end
  end

  test "routes every documented dashboard/observer/design path to an app LiveView" do
    for path <- @live_paths do
      view = live_view_for(path)
      assert view in @all_live_views, "unexpected LiveView #{inspect(view)} for GET #{path}"
    end
  end

  test "routes the root path to DashboardLive" do
    assert live_view_for("/") == DalaDev.Server.DashboardLive
  end

  test "unknown paths do not route" do
    assert live_view_for("/definitely/not/a/route") == nil
  end

  test "feature shortcut paths map to WebLive" do
    for path <- ["/devices", "/deploy", "/emulators", "/logs", "/settings"] do
      assert live_view_for(path) == DalaDev.Server.WebLive, "path #{path}"
    end
  end

  test "observer tab paths map to their tab LiveViews" do
    assert live_view_for("/observer/x@h/system") == DalaDev.Server.ObserverLive.System
    assert live_view_for("/observer/x@h/processes") == DalaDev.Server.ObserverLive.Processes
    assert live_view_for("/observer/x@h/ets") == DalaDev.Server.ObserverLive.ETS
    assert live_view_for("/cluster") == DalaDev.Server.ClusterVizLive
    assert live_view_for("/design") == DalaDev.Server.DesignLive
  end
end
