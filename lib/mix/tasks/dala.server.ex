defmodule Mix.Tasks.Dala.Server do
  use Mix.Task

  @shortdoc "Start the Dala dev server (localhost:4040)"

  @moduledoc """
  Starts the Dala dev server and opens it in the browser.

      mix dala.server
      mix dala.server --port 4040   # default port

  The server provides:
  - Live device status cards (Android + iOS simulator)
  - Per-device deploy buttons ("Update" and "First Deploy")
  - Streaming log panel (logcat / iOS simulator console)

  The server runs until you press Ctrl+C.

  For an interactive IEx session alongside the dashboard:

      iex -S mix dala.server

  ## Under the hood

  `mix dala.server` starts a Phoenix + Bandit supervision tree directly in the
  Mix process — equivalent to `iex -S mix phx.server` for a Phoenix app, except
  it starts the supervisor inline rather than through the application callback:

      Application.ensure_all_started(:bandit)
      Application.ensure_all_started(:phoenix_live_view)

      Supervisor.start_link([
        {Phoenix.PubSub, name: DalaDev.PubSub},
        DalaDev.Server.Endpoint,          # Bandit HTTP server on port 4040
        DalaDev.Server.DevicePoller,      # polls adb + xcrun simctl
        DalaDev.Server.LogStreamerSupervisor,  # logcat / simctl log streams
        DalaDev.Server.WatchWorker,       # optional file-watch loop
        ...
      ], strategy: :one_for_one)

      open "http://localhost:4040"       # macOS: open, Linux: xdg-open

  The endpoint uses `Bandit.PhoenixAdapter` instead of Cowboy, so there is no
  `:plug_cowboy` dependency. Everything else is standard Phoenix LiveView.
  """

  @default_port 4040

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])

    DalaDev.ServerDeps.ensure_available!()
    {opts, _, _} = OptionParser.parse(args, switches: [port: :integer])
    port = opts[:port] || @default_port
    lan_ip = DalaDev.Network.lan_ip()

    configure_endpoint(port, lan_ip)
    {:ok, _} = Application.ensure_all_started(:bandit)
    {:ok, _} = Application.ensure_all_started(:phoenix_live_view)

    children = [
      {Phoenix.PubSub, name: DalaDev.PubSub},
      DalaDev.Server.LogBuffer,
      DalaDev.Server.ElixirLogBuffer,
      DalaDev.Server.Endpoint,
      DalaDev.Server.DevicePoller,
      DalaDev.Server.LogStreamerSupervisor,
      DalaDev.Server.WatchWorker,
      {Task.Supervisor, name: DalaDev.Server.TaskSupervisor}
    ]

    {:ok, sup} =
      Supervisor.start_link(children, strategy: :one_for_one, name: DalaDev.Server.Supervisor)

    # Attach the Elixir logger handler now that PubSub and the buffer are up
    DalaDev.Server.ElixirLogger.attach()

    local_url = "http://localhost:#{port}"
    DalaDev.Output.info("")
    DalaDev.Output.step("Dala Dev Server")
    DalaDev.Output.success(local_url)

    if lan_ip do
      lan_url = "http://#{:inet.ntoa(lan_ip)}:#{port}"
      DalaDev.Output.success("#{lan_url}  ← open on phone")
      DalaDev.Output.info("")
      DalaDev.Output.info(DalaDev.QR.render(lan_url))
    end

    DalaDev.Output.info("")
    open_browser(local_url)

    if IEx.started?() do
      # Unlink the supervisor from this task process so it survives after run/1 returns.
      # Without this the supervisor exits when the Mix task process exits.
      Process.unlink(sup)

      DalaDev.Output.success(
        "IEx ready. Elixir log output appears in the dashboard → Elixir panel."
      )

      DalaDev.Output.info("")
    else
      DalaDev.Output.hint(
        "Tip: run iex -S mix dala.server for an interactive terminal."
      )

      DalaDev.Output.info("Press Ctrl+C to stop.")
      DalaDev.Output.info("")
      Process.sleep(:infinity)
    end
  end

  defp configure_endpoint(port, lan_ip) do
    lan_url = if lan_ip, do: "http://#{:inet.ntoa(lan_ip)}:#{port}", else: nil
    Application.put_env(:dala_dev, :dashboard_lan_url, lan_url)

    Application.put_env(:dala_dev, DalaDev.Server.Endpoint,
      adapter: Bandit.PhoenixAdapter,
      http: [ip: {0, 0, 0, 0}, port: port],
      url: [host: "localhost", port: port],
      server: true,
      live_view: [signing_salt: "dala_dev_server_salt"],
      secret_key_base: String.duplicate("dala_dev_secret_key_base_not_for_production_", 2)
    )
  end

  defp open_browser(url) do
    cmd =
      case :os.type() do
        {:unix, :darwin} -> "open"
        {:unix, _} -> "xdg-open"
        {:win32, _} -> "start"
      end

    Task.start(fn ->
      # brief pause so the server is up before the browser hits it
      :timer.sleep(500)
      System.cmd(cmd, [url], stderr_to_stdout: true)
    end)
  end
end
