defmodule Mix.Tasks.Dala.Watch do
  use Mix.Task

  @shortdoc "Watch for source changes and auto hot-push to running dala devices"

  @moduledoc """
  Watches `lib/` for source changes and automatically compiles + hot-pushes
  updated modules to all running Android and iOS devices.

  Apps must already be running. Modules are loaded in place — no restart.
  Only modules that actually changed are pushed each cycle.

  Press Ctrl-C to stop.

  Options:
    --cookie        Erlang cookie (default: dala_secret)
    --debounce      ms to wait after a change before compiling (default: 300)
    --interval      ms between file-change polls (default: 500)

  Examples:
      mix dala.watch
      mix dala.watch --debounce 500
      mix dala.watch --cookie my_cookie

  ## Under the hood

  `mix dala.watch` is an mtime-polling file watcher that drives `mix compile` and
  `nl/1` in a loop:

      # On startup:
      writes OS PID → _build/dala_watch.pid    # used by mix dala.watch_stop

      # Each cycle (every --interval ms):
      snapshot mtimes of lib/**/*.ex
      if any changed:
        :timer.sleep(debounce_ms)             # wait for format-on-save to settle
        System.cmd("mix", ["compile"])        # compile in a subprocess
        for each changed BEAM, on each node:
          :rpc.call(node, :code, :load_binary, [...])

  Compile runs in a subprocess (not `Mix.Task.run("compile")` so that Mix's
  task cache won't prevent recompilation on subsequent file saves.

  The watch loop is equivalent to running `mix compile && nl(ChangedModule)` in
  a terminal after every save — `mix dala.watch` just does it automatically.
  """

  @pid_file "_build/dala_watch.pid"

  @spec pid_file() :: String.t()
  def pid_file, do: @pid_file

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [cookie: :string, debounce: :integer, interval: :integer],
        aliases: [c: :cookie]
      )

    cookie = opts |> Keyword.get(:cookie, "dala_secret") |> String.to_atom()
    debounce = Keyword.get(opts, :debounce, 300)
    interval = Keyword.get(opts, :interval, 500)

    File.mkdir_p!("_build")
    File.write!(@pid_file, to_string(:os.getpid()))


    DalaDev.Output.step("dala.watch — watching lib/ for changes (Ctrl-C to stop)")

    nodes = connect_with_retry(cookie)

    # Initial compile + push everything so device is in sync.
    recompile()
    {pushed, _} = DalaDev.HotPush.push_all(nodes)

    if pushed > 0 do
      DalaDev.Output.success("initial push: #{pushed} module(s)")
    end

    # Snapshot source mtimes.
    sources = snapshot_sources()
    DalaDev.Output.info("Watching #{map_size(sources)} source file(s)\n")

    watch_loop(sources, nodes, cookie, debounce, interval)
  end

  # ── Loop ────────────────────────────────────────────────────────────────────

  defp watch_loop(sources, nodes, cookie, debounce, interval) do
    :timer.sleep(interval)

    current = snapshot_sources()
    changed_files = changed_sources(sources, current)

    if changed_files == [] do
      watch_loop(current, nodes, cookie, debounce, interval)
    else
      DalaDev.Output.info("◉ #{length(changed_files)} file(s) changed")

      Enum.each(changed_files, fn f ->
        DalaDev.Output.info("  #{Path.relative_to_cwd(f)}")
      end)

      # Debounce — wait in case more saves are incoming (e.g. format-on-save).
      :timer.sleep(debounce)
      current2 = snapshot_sources()

      # Re-connect if any nodes dropped (device rebooted, app restarted, etc.)
      live_nodes = reconnect_if_needed(nodes, cookie)

      snapshot = DalaDev.HotPush.snapshot_beams()
      recompile()
      {pushed, failed, modules} = DalaDev.HotPush.push_changed_detailed(live_nodes, snapshot)

      cond do
        pushed > 0 ->
          node_str = Enum.map_join(live_nodes, " ", &short_node/1)

          DalaDev.Output.success(
            "  #{pushed} module(s) → #{node_str} (#{Enum.map_join(modules, ", ", &inspect/1)})"
          )

        failed != [] ->
          Enum.each(failed, fn {mod, reason} ->
            DalaDev.Output.error("  #{mod}: #{inspect(reason)}")
          end)

        true ->
          DalaDev.Output.warn("  compile ran but no new BEAMs — syntax error?")
      end

      DalaDev.Output.info("")
      watch_loop(current2, live_nodes, cookie, debounce, interval)
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp connect_with_retry(cookie) do
    DalaDev.Output.step("Connecting to devices...")
    nodes = DalaDev.HotPush.connect(cookie: cookie)

    if nodes == [] do
      DalaDev.Output.warn("none found")
      DalaDev.Output.hint("Start apps first: mix dala.connect")
      DalaDev.Output.info("Watching anyway — will connect when nodes come up.\n")
    else
      DalaDev.Output.success("#{length(nodes)} node(s)")
      Enum.each(nodes, fn n -> DalaDev.Output.success(to_string(n)) end)
      DalaDev.Output.info("")
    end

    nodes
  end

  defp reconnect_if_needed(nodes, cookie) do
    alive = Enum.filter(nodes, &(Node.connect(&1) == true))
    new_nodes = DalaDev.HotPush.connect(cookie: cookie)
    # Union: keep existing alive nodes + any newly discovered ones
    Enum.uniq(alive ++ new_nodes)
  end

  # Lines from mix compile subprocess we don't want to echo.
  @noise_prefixes [
    "warning! Erlang/OTP",
    "Regexes will be re-compiled",
    "This can be fixed by using"
  ]

  defp recompile do
    # Run in a subprocess — Mix task caches are process-local and can't be
    # fully cleared with reenable/1 when inside another running mix task.
    mix = System.find_executable("mix") || "mix"
    {output, _} = System.cmd(mix, ["compile"], cd: File.cwd!(), stderr_to_stdout: true)

    output
    |> String.split("\n", trim: true)
    |> Enum.reject(fn line -> Enum.any?(@noise_prefixes, &String.starts_with?(line, &1)) end)
    |> Enum.each(&DalaDev.Output.info/1)
  end

  defp snapshot_sources do
    Path.wildcard("lib/**/*.ex")
    |> Map.new(fn path ->
      mtime =
        case File.stat(path, time: :posix) do
          {:ok, %{mtime: t}} -> t
          _ -> 0
        end

      {path, mtime}
    end)
  end

  defp changed_sources(old, current) do
    Enum.flat_map(current, fn {path, mtime} ->
      if Map.get(old, path) != mtime, do: [path], else: []
    end)
  end

  defp short_node(node) do
    node |> to_string() |> String.split("@") |> hd()
  end
end
