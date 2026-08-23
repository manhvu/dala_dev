defmodule Mix.Tasks.Dala.Web do
  @moduledoc """
  Start the Dala Web UI - a comprehensive web interface for all dala_dev features.

  This task starts a Phoenix + Bandit web server that provides a unified
  dashboard for all mobile development tools including device management,
  deployment, emulators, provisioning, observer, and more.

      mix dala.web
      mix dala.web --port 4000   # default port
      mix dala.web --no-browser  # don't open browser automatically

  ## Features

  The web UI provides access to:

  - **Dashboard**: Device status, quick actions, system overview
  - **Devices**: Android and iOS device management
  - **Deploy**: Application deployment to devices
  - **Emulators**: Manage Android AVDs and iOS simulators
  - **Observer**: Remote node monitoring (web-based :observer)
  - **Provision**: Code signing and provisioning profile management
  - **Release**: Build and manage releases for Android and iOS
  - **Profiling**: Performance profiling and analysis
  - **CI Testing**: Continuous integration test management
  - **Logs**: Centralized log viewing and filtering
  - **Settings**: Configuration and preferences

  ## Options

  - `--port` / `-p`: Port to run the server on (default: 4000)
  - `--no-browser`: Don't open the browser automatically
  - `--node` / `-n`: Connect to a remote node
  - `--name`: Node name for distributed mode
  - `--cookie`: Cookie for distributed mode

  ## Examples

      mix dala.web
      mix dala.web --port 8080
      mix dala.web --no-browser
      mix dala.web --node other@host --name mynode
  """

  use Mix.Task

  @default_port 4000

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          port: :integer,
          browser: :boolean,
          node: :string,
          name: :string,
          cookie: :string
        ],
        aliases: [p: :port, n: :node]
      )

    port = Keyword.get(opts, :port, @default_port)
    open_browser? = Keyword.get(opts, :browser, true)
    target_node = Keyword.get(opts, :node, nil)
    node_name = Keyword.get(opts, :name, nil)
    cookie = Keyword.get(opts, :cookie, :erlang.get_cookie())

    # Setup distributed node if requested
    if node_name do
      {:ok, _} = Node.start(:"#{node_name}", :shortnames)
    end

    if cookie do
      Node.set_cookie(cookie |> to_string() |> String.to_atom())
    end

    if target_node do
      target = target_node |> to_string() |> String.to_atom()

      case Node.connect(target) do
        true -> DalaDev.Output.success("Connected to #{target}")
        false -> DalaDev.Output.error("Failed to connect to #{target}")
      end
    end

    # Configure the endpoint
    configure_endpoint(port)
    lan_ip = DalaDev.Network.lan_ip()

    # Start required applications
    DalaDev.ServerDeps.ensure_available!()
    {:ok, _} = Application.ensure_all_started(:bandit)
    {:ok, _} = Application.ensure_all_started(:phoenix_live_view)
    {:ok, _} = Application.ensure_all_started(:phoenix_pubsub)

    # Start supervisor with all components
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

    # Attach the Elixir logger handler
    DalaDev.Server.ElixirLogger.attach()

    # Print startup information
    local_url = "http://localhost:#{port}"
    DalaDev.Output.info("")
    DalaDev.Output.step("Dala Web UI")
    DalaDev.Output.success(local_url)
    DalaDev.Output.info("All dala_dev features available at:")
    DalaDev.Output.info("#{local_url}/dashboard")
    DalaDev.Output.info("#{local_url}/devices")
    DalaDev.Output.info("#{local_url}/deploy")
    DalaDev.Output.info("#{local_url}/emulators")
    DalaDev.Output.info("#{local_url}/observer")
    DalaDev.Output.info("#{local_url}/provision")
    DalaDev.Output.info("#{local_url}/release")
    DalaDev.Output.info("#{local_url}/profiling")
    DalaDev.Output.info("#{local_url}/ci")
    DalaDev.Output.info("#{local_url}/logs")

    if lan_ip do
      lan_url = "http://#{:inet.ntoa(lan_ip)}:#{port}"
      DalaDev.Output.info("")
      DalaDev.Output.success("LAN: #{lan_url}  ← open on phone")
      DalaDev.Output.info("")
      DalaDev.Output.info(DalaDev.QR.render(lan_url))
    end

    DalaDev.Output.info("")

    # Open browser if requested
    if open_browser? do
      open_browser(local_url)
    end

    if IEx.started?() do
      Process.unlink(sup)
      DalaDev.Output.success("IEx ready.")
      DalaDev.Output.info("")
    else
      DalaDev.Output.info("Press Ctrl+C to stop.")
      DalaDev.Output.info("")
      Process.sleep(:infinity)
    end
  end

  defp configure_endpoint(port) do
    Application.put_env(:dala_dev, DalaDev.Server.Endpoint,
      adapter: Bandit.PhoenixAdapter,
      http: [ip: {0, 0, 0, 0}, port: port],
      url: [host: "localhost", port: port],
      server: true,
      live_view: [signing_salt: "dala_dev_web_salt"],
      secret_key_base: String.duplicate("dala_dev_web_secret_key_base_not_for_production_", 2)
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
      :timer.sleep(500)
      System.cmd(cmd, [url], stderr_to_stdout: true)
    end)
  end
end
