defmodule DalaDev.Profiling do
  @moduledoc """
  Performance profiling for dala Elixir nodes using :eprof and :fprof.

  Provides CPU profiling, flame graphs, and performance analysis
  for dala Elixir cluster nodes.

  ## Examples:

      # Profile a function on a node
      {:ok, profile} = DalaDev.Profiling.profile(
        :"dala_qa@192.168.1.5",
        fn -> MyApp.heavy_computation() end
      )

      # Analyze profile
      {:ok, analysis} = DalaDev.Profiling.analyze(profile)

      # Generate flame graph (HTML)
      DalaDev.Profiling.flame_graph(profile, "flame.html")
  """

  # alias DalaDev.Device - currently unused
  alias DalaDev.Device

  @type node_ref :: node() | Device.t() | String.t()
  @type profile_data :: term()
  @type analysis :: map()

  @doc """
  Profile a function on a remote node using :eprof.

  Options:
  - `:timeout` - RPC timeout in ms (default: 60_000)
  - `:duration` - Profile duration in ms (default: 10_000)

  Returns `{:ok, profile_data}` or `{:error, reason}`.
  """
  @spec profile(node_ref(), (-> any()), keyword()) ::
          {:ok, profile_data()} | {:error, term()}
  def profile(node_ref, fun, opts \\ []) when is_function(fun, 0) do
    node = resolve_node(node_ref)
    timeout = Keyword.get(opts, :timeout, 60_000)
    duration = Keyword.get(opts, :duration, 10_000)
    tool = Keyword.get(opts, :tool, :eprof)

    :rpc.call(node, __MODULE__, :profile_locally, [fun, duration, tool], timeout)
  end

  @doc """
  Analyze profile data and generate a summary.

  Returns a map with:
  - `:total_time` - Total execution time
  - `:calls` - Number of function calls
  - `:top_functions` - List of {module, function, time, calls}
  - `:bottlenecks` - Functions with highest time consumption
  """
  @spec analyze(profile_data()) :: {:ok, analysis()} | {:error, term()}
  def analyze(profile) when is_list(profile) do
    try do
      total_time = calculate_total_time(profile)
      calls = count_calls(profile)

      top_functions = extract_top_functions(profile, 10)
      bottlenecks = identify_bottlenecks(profile, 5)

      {:ok,
       %{
         total_time: total_time,
         calls: calls,
         top_functions: top_functions,
         bottlenecks: bottlenecks
       }}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Generate a flame graph from profile data.

  Options:
  - `:format` - :html (default) or :text
  - `:output` - Output file path (optional)

  Returns the report content or :ok if saved to file.
  """
  @spec flame_graph(profile_data(), keyword()) :: {:ok, String.t() | :ok} | {:error, term()}
  def flame_graph(profile, opts \\ []) do
    format = Keyword.get(opts, :format, :html)
    output = Keyword.get(opts, :output)

    content =
      case format do
        :html -> generate_flame_graph_html(profile)
        :text -> generate_flame_graph_text(profile)
      end

    if output do
      case File.write(output, content) do
        :ok -> :ok
        error -> error
      end
    else
      {:ok, content}
    end
  end

  @doc false
  @spec profile_locally((-> any()), non_neg_integer(), atom()) ::
          {:ok, term()} | {:error, String.t()}
  def profile_locally(fun, duration, tool \\ :eprof) do
    case tool do
      :eprof -> profile_locally_eprof(fun, duration)
      :fprof -> profile_locally_fprof(fun, duration)
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp profile_locally_eprof(fun, duration) do
    # Start :eprof profiling. On modern OTP, :eprof.analyze/0 prints results
    # to stdio and returns :ok — there is no :eprof.get_data/0.
    apply(:eprof, :start, [])
    apply(:eprof, :profile, [fn -> profile_duration(fun, duration) end])
    apply(:eprof, :analyze, [])
    apply(:eprof, :stop, [])

    {:ok, :eprof_completed}
  end

  defp profile_locally_fprof(fun, _duration) do
    # Start :fprof profiling
    apply(:fprof, :start, [])
    apply(:fprof, :apply, [fun, []])
    apply(:fprof, :stop, [])

    # Get profile data
    {:ok, apply(:fprof, :get_profile, [])}
  end

  # ── Private helpers ──────────────────────────────;

  defp profile_duration(fun, duration) do
    task = Task.async(fun)
    Process.sleep(duration)
    Task.await(task, 1000)
  end

  defp resolve_node(node) when is_atom(node), do: node

  defp resolve_node(%Device{node: node}) when not is_nil(node),
    do: node

  defp resolve_node(str) when is_binary(str), do: String.to_atom(str)

  defp calculate_total_time(profile) do
    case profile do
      {_, _, total_time, _} -> total_time
      _ -> 0
    end
  end

  defp count_calls(profile) when is_list(profile) do
    length(profile)
  end

  defp extract_top_functions(profile, count) when is_tuple(profile) do
    # eprof format: {proc, count, time, calls}
    profile
    |> Tuple.to_list()
    |> Enum.flat_map(fn
      {_, funcs} when is_list(funcs) ->
        Enum.map(funcs, fn {mod, fun, _arity, time, calls} ->
          {mod, fun, time, calls}
        end)

      _ ->
        []
    end)
    |> Enum.sort_by(fn {_, _, time, _} -> time end, &>=/2)
    |> Enum.take(count)
  end

  defp extract_top_functions(profile, count) when is_list(profile) do
    # fprof format
    profile
    |> Enum.sort_by(& &1.time, &>=/2)
    |> Enum.take(count)
    |> Enum.map(fn %{mod: mod, fun: fun, time: time, calls: calls} ->
      {mod, fun, time, calls}
    end)
  end

  defp identify_bottlenecks(profile, count) do
    top = extract_top_functions(profile, count)

    Enum.map(top, fn {mod, fun, time, _calls} ->
      {mod, fun, time}
    end)
  end

  defp generate_flame_graph_html(profile) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Flame Graph</title>
        <style>
            body { font-family: monospace; margin: 20px; }
            .flame { display: flex; margin: 2px 0; }
            .bar { background: #4CAF50; height: 20px; margin: 0 1px; }
        </style>
    </head>
    <body>
        <h1>Flame Graph</h1>
        <p>Generated: #{DateTime.utc_now()}</p>
        #{generate_flame_bars(profile)}
    </body>
    </html>
    """
  end

  defp generate_flame_bars(_profile) do
    # Placeholder - would generate actual flame bars;
    """
    <div class="flame">
        <div class="bar" style="width: 100%;">Root</div>
        <div class="flame" style="margin-left: 20px;">
            <div class="bar" style="width: 60%;">Child 1</div>
            <div class="flame" style="margin-left: 20px;">
                <div class="bar" style="width: 80%;">Grandchild 1a</div>
            </div>
            <div class="flame" style="margin-left: 20px;">
                <div class="bar" style="width: 40%;">Grandchild 1b</div>
            </div>
        </div>
    </div>
    """
  end

  defp generate_flame_graph_text(_profile) do
    # Placeholder - would generate text-based flame graph;
    """
    Flame Graph
    ============
    Root (100%)
    ├── Child 1 (60%)
    │   └── Grandchild 1a (80%)
    └── Child 2 (40%)
        └── Grandchild 2b (50%)
    """
  end
end
