defmodule Mix.Tasks.Dala.Trace do
  use Mix.Task

  @shortdoc "Distributed tracing for dala Elixir clusters"

  @moduledoc """
  Interactive distributed tracing UI for dala Elixir clusters.

  ## Usage

      mix dala.trace                          # interactive tracing UI
      mix dala.trace --node dala_qa@192.168.1.5  # trace specific node
      mix dala.trace --export trace.json      # export to Chrome Tracing format
      mix dala.trace --modules Dala.Ui.Socket,MyApp  # trace specific modules

  ## Options

    * `--node` - Target node (can be specified multiple times)
    * `--export` - Export traces to file (Chrome Tracing JSON format)
    * `--modules` - Comma-separated list of modules to trace
    * `--functions` - Comma-separated list of module:function:arity to trace
    * `--duration` - Trace duration in seconds (default: 60)

  ## Examples

      # Start interactive tracing
      mix dala.trace

      # Trace specific modules on a node
      mix dala.trace --node dala_qa@192.168.1.5 --modules MyApp,MyAppWeb

      # Export to Chrome Tracing format
      mix dala.trace --export trace.json --duration 30
  """

  alias DalaDev.Tracing

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])

    Mix.Task.run("app.config")

    {parsed_opts, _} =
      OptionParser.parse(args,
        strict: [
          node: :keep,
          export: :string,
          modules: :string,
          functions: :string,
          duration: :integer
        ]
      )

    nodes = Keyword.get_values(parsed_opts, :node)
    export_path = Keyword.get(parsed_opts, :export)
    modules_str = Keyword.get(parsed_opts, :modules, "")
    functions_str = Keyword.get(parsed_opts, :functions, "")
    duration = Keyword.get(parsed_opts, :duration, 60)

    nodes = if nodes == [], do: [:all], else: Enum.map(nodes, &String.to_atom/1)

    modules = parse_modules(modules_str)
    functions = parse_functions(functions_str)

    trace_opts = []

    trace_opts =
      if modules != [], do: Keyword.put(trace_opts, :modules, modules), else: trace_opts

    trace_opts =
      if functions != [], do: Keyword.put(trace_opts, :functions, functions), else: trace_opts

    DalaDev.Output.info("Starting trace on nodes: #{inspect(nodes)}")
    DalaDev.Output.info("Duration: #{duration} seconds")

    case Tracing.start_trace(nodes, trace_opts) do
      {:ok, trace_id} ->
        DalaDev.Output.success("Trace started with ID: #{inspect(trace_id)}")

        Process.sleep(duration * 1000)

        DalaDev.Output.step("Collecting traces")

        traces = Tracing.get_events(trace_id)
        DalaDev.Output.info("Collected #{length(traces)} trace events")

        if export_path do
          case Tracing.export_chrome_trace(trace_id, export_path) do
            :ok ->
              DalaDev.Output.success("Exported to: #{export_path}")

            error ->
              DalaDev.Output.error("Export failed: #{inspect(error)}")
          end
        else
          print_traces(traces)
        end

        Tracing.stop_trace(trace_id)

      {:error, reason} ->
        DalaDev.Output.error("Failed to start trace: #{inspect(reason)}")
    end
  end

  defp parse_modules(""), do: []

  defp parse_modules(str),
    do: str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.map(&String.to_atom/1)

  defp parse_functions(""), do: []

  defp parse_functions(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn func_spec ->
      case String.split(func_spec, ":") do
        [mod, fun, arity] -> {String.to_atom(mod), String.to_atom(fun), String.to_integer(arity)}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp print_traces(traces) do
    Enum.each(traces, fn trace ->
      DalaDev.Output.info("[#{trace[:type]}] #{trace[:module]}.#{trace[:function]} - #{trace[:pid]}")
    end)
  end
end
