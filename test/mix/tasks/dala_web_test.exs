defmodule Mix.Tasks.Dala.WebTest do
  use ExUnit.Case, async: false

  # `mix dala.web` blocks forever once booted, so exercise the pieces run/1
  # wires together instead of invoking it: the optional server deps must be
  # loadable and the router must serve the UI surface run/1 advertises.
  describe "run/1 prerequisites" do
    test "server dependencies required by run/1 are available" do
      assert Code.ensure_loaded?(Mix.Tasks.Dala.Web)
      assert DalaDev.ServerDeps.available?() == true
    end

    test "router serves the dashboard path run/1 prints at startup" do
      info = Phoenix.Router.route_info(DalaDev.Server.Router, "GET", "/dashboard", "localhost")
      assert %{route: "/dashboard", log_module: DalaDev.Server.DashboardLive} = info

      # The routed view must be a compiled, mountable LiveView module.
      assert %{kind: :view} = DalaDev.Server.DashboardLive.__live__()
      assert function_exported?(DalaDev.Server.DashboardLive, :mount, 3)
    end
  end

  test "is registered as mix dala.web and documents itself" do
    assert Mix.Task.get("dala.web") == Mix.Tasks.Dala.Web

    {:docs_v1, _, _, _, moduledoc, _, _} = Code.fetch_docs(Mix.Tasks.Dala.Web)

    assert doc_string(moduledoc) =~ "Dala Web UI"
  end

  defp doc_string(%{"en" => doc}), do: doc
  defp doc_string(doc) when is_binary(doc), do: doc
  defp doc_string(_), do: ""
end
