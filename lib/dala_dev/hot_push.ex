defmodule DalaDev.HotPush do
  @moduledoc """
  Connects to already-running device nodes and hot-pushes BEAM modules via RPC.

  Unlike `DalaDev.Deployer`, this does NOT restart apps — modules are loaded
  into the running BEAM in place, just like `nl/1` in IEx.

  Requires apps to already be running (start with `mix dala.connect` or
  `mix dala.deploy` first).
  """

  alias DalaDev.{Tunnel}
  alias DalaDev.Discovery.{Android, IOS}

  @cookie :dala_secret

  @doc """
  Sets up adb tunnels (idempotent) and connects to all running device nodes.

  Returns list of connected node atoms.

  ## Options

  - `:cookie` - Erlang cookie (default: `:dala_secret`)
  - `:device` - Target specific device by ID (optional)
  """
  @spec connect(keyword()) :: [node()]
  def connect(opts \\ []) do
    cookie = Keyword.get(opts, :cookie, @cookie)
    device_id = Keyword.get(opts, :device, nil)

    nodes =
      (Android.list_devices() ++ IOS.list_simulators())
      |> filter_by_device_id(device_id)
      |> Enum.with_index()
      |> Enum.flat_map(fn {device, idx} ->
        case Tunnel.setup(device, idx) do
          {:ok, d} -> [d]
          _ -> []
        end
      end)
      |> Enum.flat_map(fn device ->
        ensure_local_dist(cookie)
        Node.set_cookie(device.node, cookie)

        case Node.connect(device.node) do
          true -> [device.node]
          _ -> []
        end
      end)

    nodes
  end

  defp filter_by_device_id(devices, nil), do: devices

  defp filter_by_device_id(devices, device_id) do
    Enum.filter(devices, &DalaDev.Device.match_id?(&1, device_id))
  end

  @doc """
  Pushes all compiled BEAM files from the current environment's build directory (`_build/<env>/lib/*/ebin/`) to `nodes`.

  Only pushes BEAMs for runtime dependencies — deps marked `only: :dev` or
  `runtime: false` in `mix.exs` (and their transitive deps) are excluded.
  This prevents dev tooling (dala_dev, Bandit, Phoenix, etc.) from being pushed
  to the device when using `path:` deps during local framework development.

  Returns `{pushed_count, failed_list}`.
  """
  @spec push_all([node()]) :: {non_neg_integer(), list()}
  def push_all(nodes) do
    beams = runtime_beam_paths()
    push_beams(nodes, beams)
  end

  @doc """
  Pushes all compiled BEAM files to devices specified by ID.

  Convenience function that combines `connect/1` and `push_all/1`.
  """
  @spec push_all_to_device(String.t(), keyword()) :: {non_neg_integer(), list()}
  def push_all_to_device(device_id, opts \\ []) do
    cookie = Keyword.get(opts, :cookie, @cookie)
    nodes = connect(cookie: cookie, device: device_id)

    if nodes == [] do
      {:error, "No running node found for device: #{device_id}"}
    else
      push_all(nodes)
    end
  end

  @doc """
  Takes a snapshot of current BEAM mtimes for runtime deps only.
  Pass the result to `push_changed/2` before and after compiling to get only
  the modules that actually changed.
  """
  @spec snapshot_beams() :: %{String.t() => non_neg_integer()}
  def snapshot_beams do
    runtime_beam_paths()
    |> Map.new(fn path ->
      mtime =
        case File.stat(path, time: :posix) do
          {:ok, %{mtime: t}} -> t
          _ -> 0
        end

      {path, mtime}
    end)
  end

  @doc """
  Pushes BEAM files that changed since `snapshot` (from `snapshot_beams/0`).
  Returns `{pushed_count, failed_list}` — pushed_count is 0 if nothing changed.
  """
  @spec push_changed([node()], %{String.t() => non_neg_integer()}) :: {non_neg_integer(), list()}
  def push_changed(nodes, snapshot) do
    {pushed, failed, _modules} = push_changed_detailed(nodes, snapshot)
    {pushed, failed}
  end

  @doc """
  Like `push_changed/2` but also returns the list of pushed module names.
  Returns `{pushed_count, failed_list, module_names}` — used by `mix dala.watch`
  to show exactly what was hot-pushed on each save.
  """
  @spec push_changed_detailed([node()], %{String.t() => non_neg_integer()}) ::
          {non_neg_integer(), list(), [module()]}
  def push_changed_detailed(nodes, snapshot) do
    beams =
      runtime_beam_paths()
      |> Enum.filter(fn path ->
        current_mtime =
          case File.stat(path, time: :posix) do
            {:ok, %{mtime: t}} -> t
            _ -> 0
          end

        current_mtime != Map.get(snapshot, path, 0)
      end)

    push_beams_detailed(nodes, beams)
  end

  # ── Runtime dep filtering ────────────────────────────────────────────────────

  # Build path for the current Mix environment. Never hardcode `_build/dev` —
  # running under MIX_ENV=test or prod must not silently push nothing.
  defp build_lib_dir do
    Path.join([Mix.Project.build_path(), "lib"])
  end

  # Returns only BEAM paths that belong to the app's runtime dependency tree.
  # Excludes deps marked only: :dev or runtime: false in mix.exs, and all of
  # their transitive deps (resolved via OTP .app files).
  defp runtime_beam_paths do
    runtime = runtime_lib_names()

    Path.wildcard(Path.join(build_lib_dir(), "*/ebin/*.beam"))
    |> Enum.filter(fn path ->
      lib = path |> Path.split() |> Enum.at(-3)
      MapSet.member?(runtime, lib)
    end)
  end

  @doc """
  Returns ebin directories for runtime deps only (no dev-only tooling).
  Used by `Deployer` so the filesystem push matches the dist push scope.
  """
  @spec runtime_beam_dirs() :: [String.t()]
  def runtime_beam_dirs do
    runtime = runtime_lib_names()
    lib_dir = build_lib_dir()

    case File.ls(lib_dir) do
      {:ok, libs} ->
        libs
        |> Enum.filter(&MapSet.member?(runtime, &1))
        |> Enum.map(&Path.join([lib_dir, &1, "ebin"]))
        |> Enum.filter(&File.dir?/1)

      {:error, _} ->
        []
    end
  end

  defp runtime_lib_names do
    project_app = to_string(Mix.Project.config()[:app])

    # Direct runtime deps: no only: :dev and not runtime: false
    direct =
      Mix.Project.config()
      |> Keyword.get(:deps, [])
      |> Enum.flat_map(&dep_runtime_name/1)
      |> MapSet.new()
      |> MapSet.put(project_app)

    expand_runtime_libs(direct)
  end

  # Expand a set of lib names to include their transitive OTP deps,
  # by reading each lib's .app file in the current env's build dir.
  defp expand_runtime_libs(libs) do
    new_libs =
      Enum.flat_map(libs, fn lib ->
        case Path.wildcard(Path.join(build_lib_dir(), "#{lib}/ebin/*.app")) do
          [app_file | _] ->
            case :file.consult(String.to_charlist(app_file)) do
              {:ok, [{:application, _app, props}]} ->
                (props[:applications] || []) |> Enum.map(&to_string/1)

              _ ->
                []
            end

          [] ->
            []
        end
      end)
      |> MapSet.new()
      |> MapSet.difference(libs)

    if MapSet.size(new_libs) == 0 do
      libs
    else
      expand_runtime_libs(MapSet.union(libs, new_libs))
    end
  end

  # Returns the app name as a string if this dep is a runtime dep, else [].
  defp dep_runtime_name(dep) do
    {app, opts} =
      case dep do
        {app, _version, opts} when is_list(opts) -> {app, opts}
        {app, opts} when is_list(opts) -> {app, opts}
        {app, _version} -> {app, []}
        app when is_atom(app) -> {app, []}
      end

    only = Keyword.get(opts, :only)
    runtime = Keyword.get(opts, :runtime, true)
    dev_only = only == :dev or only == [:dev] or (is_list(only) and only == [:dev])
    if dev_only or not runtime, do: [], else: [to_string(app)]
  end

  # ── Private ─────────────────────────────────────────────────────────────────

  defp push_beams(_nodes, []), do: {0, []}

  defp push_beams(nodes, beam_files) do
    {pushed, failed, _} = push_beams_detailed(nodes, beam_files)
    {pushed, failed}
  end

  defp push_beams_detailed(_nodes, []), do: {0, [], []}

  defp push_beams_detailed(nodes, beam_files) do
    results =
      Enum.map(beam_files, fn path ->
        module = beam_path_to_module(path)

        case File.read(path) do
          {:ok, binary} -> load_on_nodes(nodes, module, path, binary)
          {:error, reason} -> {:error, {module, reason}}
        end
      end)

    pushed_modules =
      for {:ok, module} <- results, do: module

    failed = for {:error, pair} <- results, do: pair
    {length(pushed_modules), failed, pushed_modules}
  end

  defp load_on_nodes(nodes, module, path, binary) do
    fname = String.to_charlist(path)
    # 10 seconds
    rpc_timeout = 10_000

    errors =
      Enum.flat_map(nodes, fn node ->
        case :rpc.call(node, :code, :load_binary, [module, fname, binary], rpc_timeout) do
          {:module, ^module} -> []
          # NIF modules already loaded — safe to ignore
          {:error, :on_load_failure} -> []
          {:badrpc, reason} -> [{node, DalaDev.Error.format({:error, reason})}]
          {:error, reason} -> [{node, DalaDev.Error.format({:error, reason})}]
        end
      end)

    if errors == [], do: {:ok, module}, else: {:error, {module, errors}}
  end

  defp beam_path_to_module(path) do
    path |> Path.basename(".beam") |> String.to_atom()
  end

  defp ensure_local_dist(cookie) do
    unless Node.alive?() do
      Node.start(:"dala_dev@127.0.0.1", :longnames)
      Node.set_cookie(cookie)
    end
  end
end
