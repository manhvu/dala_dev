defmodule DalaDev.Connector do
  @moduledoc """
  Orchestrates device discovery, tunnel setup, app restart, and node connection.
  """

  alias DalaDev.{Device, Tunnel}
  alias DalaDev.Discovery.{Android, IOS}

  @android_activity ".MainActivity"

  defp bundle_id, do: DalaDev.Config.bundle_id()
  defp android_package, do: bundle_id()
  defp ios_bundle_id, do: bundle_id()
  # ms to wait for node to appear
  @connect_timeout 25_000
  # ms between polls
  @connect_interval 500

  @doc """
  Discovers all connected devices, sets up tunnels, restarts apps, and waits
  for Erlang nodes to come online.

  Returns {connected, failed} lists of %Device{}.
  """
  @spec connect_all(keyword()) :: {[Device.t()], [Device.t()]}
  def connect_all(opts \\ []) do
    cookie = Keyword.get(opts, :cookie, :dala_secret)

    DalaDev.Output.step("Scanning for devices")
    DalaDev.Output.info("")

    devices = discover_all()

    if devices == [] do
      DalaDev.Output.warn("No devices found.")
      DalaDev.Output.hint("Connect an Android device via USB and enable USB debugging")
      DalaDev.Output.hint("Start an iOS simulator in Xcode or via xcrun simctl")
      {[], []}
    else
      print_discovered(devices)

      # Set up tunnels (assigns dist_port per device)
      {tunneled, failed_tunnel} = setup_tunnels(devices)

      # Kill any stale simulator processes from previous sessions. A lingering
      # BEAM holds its EPMD slot, blocking new instances from registering.
      kill_stale_simulator_apps(tunneled)

      # Restart apps so they pick up tunnels and use correct node names
      Enum.each(tunneled, &restart_app/1)

      # Start distribution on the Mac side
      ensure_local_dist(cookie)

      # Activate accessibility on iOS simulators so ui_tree() returns elements.
      # SwiftUI lazily populates its a11y tree; this one-time activation persists
      # for the simulator session (survives app restarts).
      tunneled
      |> Enum.filter(&(&1.platform == :ios))
      |> Enum.each(fn d -> IOS.enable_accessibility(d.serial) end)

      # Wait for nodes to come online
      DalaDev.Output.info("\n  Waiting for nodes...")
      {connected, failed_wait} = wait_for_nodes(tunneled, cookie)

      # Report failures
      all_failed = failed_tunnel ++ failed_wait

      Enum.each(all_failed, fn d ->
        DalaDev.Output.error("  #{d.name || d.serial}: #{d.error}")
        print_fix_hint(d)
      end)

      if connected != [] do
        DalaDev.Output.success("Connected cluster (#{length(connected)} node(s)):")

        Enum.each(connected, fn d ->
          DalaDev.Output.info("  ✓ #{d.node}  [port #{d.dist_port}]")
        end)
      end

      {connected, all_failed}
    end
  end

  defp discover_all do
    android = Android.list_devices()
    ios = IOS.list_devices()
    android ++ ios
  end

  defp setup_tunnels(devices) do
    # Track index per platform to assign unique ports
    devices
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {device, idx}, {ok, fail} ->
      IO.write("  #{device.name || device.serial}  →  tunneling...")

      case Tunnel.setup(device, idx) do
        {:ok, d} ->
          DalaDev.Output.info(" done")
          {ok ++ [d], fail}

        {:error, reason} ->
          DalaDev.Output.info(" failed")
          {ok, fail ++ [%{device | status: :error, error: reason}]}
      end
    end)
  end

  # Kill any app processes running in simulators that are NOT in our current
  # tunneled set. A stale BEAM from a previous session holds its EPMD slot,
  # blocking new instances of the same node name from registering.
  defp kill_stale_simulator_apps(tunneled) do
    active =
      tunneled
      |> Enum.filter(&(&1.platform == :ios && &1.type == :simulator))
      |> Enum.map(& &1.serial)
      |> MapSet.new()

    case System.cmd("pgrep", ["-fl", bundle_id()], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.each(fn line ->
          with [pid_str | _] <- String.split(line, " ", parts: 2),
               {pid, ""} <- Integer.parse(pid_str),
               [_, udid] <- Regex.run(~r|/Devices/([0-9A-F-]{36})/|i, line),
               false <- MapSet.member?(active, udid) do
            System.cmd("kill", ["-9", to_string(pid)], stderr_to_stdout: true)
          end
        end)

      _ ->
        :ok
    end

    :timer.sleep(300)
  end

  defp restart_app(%Device{platform: :android, serial: serial, dist_port: port}) do
    IO.write("  Restarting app on #{serial}...")
    Android.restart_app(serial, android_package(), @android_activity, dist_port: port)
    DalaDev.Output.info(" done")
  end

  defp restart_app(%Device{platform: :ios, type: :physical, serial: udid}) do
    IO.write("  Restarting app on #{udid}...")
    # dala_beam.m discovers the USB link-local IP via getifaddrs() — no env vars needed.
    IOS.restart_app_physical(udid, ios_bundle_id())
    DalaDev.Output.info(" done")
  end

  defp restart_app(%Device{platform: :ios, serial: udid, dist_port: port}) do
    IO.write("  Restarting app on #{udid}...")
    IOS.terminate_app(udid, ios_bundle_id())
    :timer.sleep(500)
    IOS.launch_app(udid, ios_bundle_id(), dist_port: port)
    DalaDev.Output.info(" done")
  end

  defp ensure_local_dist(cookie) do
    unless Node.alive?() do
      # On Nix and some Linux setups, EPMD is not started automatically.
      # Try to start it before Node.start so distribution can register.
      start_epmd()
      handle_dist_start(Node.start(:"dala_dev@127.0.0.1", :longnames), cookie)
    end
  end

  # Attempt to start EPMD in daemon mode. Safe to call when already running —
  # epmd -daemon exits 0 immediately in that case.
  # Public for testing.
  @doc false
  @spec start_epmd() :: {String.t(), non_neg_integer()} | :ok
  def start_epmd do
    System.cmd("epmd", ["-daemon"], stderr_to_stdout: true)
  rescue
    # epmd not in PATH — Node.start will surface a clear error
    _ -> :ok
  end

  # Handle the return value of Node.start/2.
  # Public for testing.
  @doc false
  @spec handle_dist_start({:ok, term()} | {:error, term()}, atom()) :: :ok
  def handle_dist_start({:ok, _}, cookie),
    do: Node.set_cookie(cookie)

  def handle_dist_start({:error, {:already_started, _}}, cookie),
    do: Node.set_cookie(cookie)

  def handle_dist_start({:error, reason}, _cookie) do
    Mix.raise("""
    Failed to start Erlang distribution: #{inspect(reason)}

    EPMD (Erlang Port Mapper Daemon) may not be running or reachable.
    Try starting it manually:

        epmd -daemon

    Then retry: mix dala.connect
    Run `mix dala.doctor` for a full environment diagnosis.
    """)
  end

  defp wait_for_nodes(devices, cookie) do
    # Start all connection attempts in parallel so slow starters (simulators
    # that need ~20s to boot their BEAM) don't consume the other devices' budget.
    # Total wall time = max(individual connect times), not sum.
    tasks =
      Enum.map(devices, fn device ->
        {device, Task.async(fn -> wait_for_node(device.node, cookie, @connect_timeout) end)}
      end)

    Enum.reduce(tasks, {[], []}, fn {device, task}, {ok, fail} ->
      IO.write("  #{device.node} ...")

      case Task.await(task, @connect_timeout + 2_000) do
        :ok ->
          DalaDev.Output.info(" done")
          {ok ++ [%{device | status: :connected}], fail}

        {:error, reason} ->
          DalaDev.Output.info(" failed")
          {ok, fail ++ [%{device | status: :error, error: reason}]}
      end
    end)
  end

  defp wait_for_node(node, _cookie, timeout) when timeout <= 0 do
    {:error, "timed out waiting for #{node}"}
  end

  defp wait_for_node(node, cookie, timeout) do
    Node.set_cookie(node, cookie)

    case Node.connect(node) do
      true ->
        :ok

      false ->
        :timer.sleep(@connect_interval)
        wait_for_node(node, cookie, timeout - @connect_interval)

      :ignored ->
        {:error, "local node not alive (distribution not started)"}
    end
  end

  defp print_discovered(devices) do
    android = Enum.filter(devices, &(&1.platform == :android))
    ios = Enum.filter(devices, &(&1.platform == :ios))

    if android != [] do
      DalaDev.Output.info("  Android")

      Enum.each(android, fn d ->
        status = if d.status == :unauthorized, do: "unauthorized", else: "found"

        DalaDev.Output.info("  ├── #{d.name || d.serial}  #{d.serial}  #{status}")

        if d.status == :unauthorized,
          do: DalaDev.Output.error("  │   #{d.error}")
      end)
    end

    if ios != [] do
      DalaDev.Output.info("  iOS")

      Enum.each(ios, fn d ->
        DalaDev.Output.info("  ├── #{d.name || d.serial}  #{d.serial}  found")
      end)
    end

    DalaDev.Output.info("")
  end

  defp print_fix_hint(%Device{status: :unauthorized}) do
    DalaDev.Output.hint("Check your device for a 'Allow USB debugging?' prompt")
    DalaDev.Output.hint("If no prompt: Settings → Developer Options → Revoke USB debugging")
  end

  defp print_fix_hint(%Device{platform: :android, error: error})
       when is_binary(error) do
    if String.contains?(error, "timed out") do
      DalaDev.Output.hint("Is the app installed? Run: mix dala.deploy")
      DalaDev.Output.hint("Android distribution starts 3s after app launch")
    end
  end

  defp print_fix_hint(_), do: :ok
end
