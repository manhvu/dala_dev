defmodule Mix.Tasks.Dala.Logs do
  use Mix.Task

  @shortdoc "Collect and stream logs from mobile devices and cluster nodes"

  @moduledoc """
  Collects, streams, and exports logs from dala Elixir cluster nodes.

  ## Examples

      # Stream all logs in real-time
      mix dala.logs

      # Stream logs from a specific node
      mix dala.logs --node dala_qa@192.168.1.5

      # Filter by log level
      mix dala.logs --level error

      # Save logs to file
      mix dala.logs --save logs.jsonl --format jsonl

      # Show last N entries
      mix dala.logs --last 100

  ## Options

    * `--node` - Node to collect logs from (can be repeated)
    * `--level` - Minimum log level (error, warning, info, debug)
    * `--save` - Save logs to file
    * `--format` - Output format (text, jsonl, csv)
    * `--last` - Number of recent entries to show
    * `--follow` - Follow mode (stream continuously, like tail -f)

  ## Formats

    * `text` - Human-readable text (default)
    * `jsonl` - JSON Lines format (one JSON object per line)
    * `csv` - CSV format with headers
  """

  alias DalaDev.LogCollector

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])

    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          node: [:string, :keep],
          level: :string,
          save: :string,
          format: :string,
          last: :integer,
          follow: :boolean
        ],
        aliases: [
          n: :node,
          l: :level,
          s: :save,
          f: :format
        ]
      )

    nodes = Keyword.get_values(opts, :node)
    level = Keyword.get(opts, :level, "info") |> String.to_atom()
    save_path = Keyword.get(opts, :save)
    format = Keyword.get(opts, :format, "text") |> String.to_atom()
    last = Keyword.get(opts, :last, 100)
    follow = Keyword.get(opts, :follow, false)

    node_ref = if nodes == [], do: :all_nodes, else: nodes

    collect_opts = [level: level, last: last]

    if follow do
      stream_logs(node_ref, level, save_path, format)
    else
      collect_and_display(node_ref, collect_opts, save_path, format)
    end
  end

  defp collect_and_display(node_ref, opts, save_path, format) do
    case LogCollector.collect_logs(node_ref, opts) do
      {:ok, logs} ->
        if save_path do
          case LogCollector.export_logs(save_path, nodes: node_ref, format: format) do
            :ok ->
              DalaDev.Output.success("Logs saved to #{save_path}")

            {:error, reason} ->
              DalaDev.Output.error("Failed to save logs: #{inspect(reason)}")
          end
        else
          display_logs(logs, format)
        end

      {:error, reason} ->
        DalaDev.Output.error("Failed to collect logs: #{inspect(reason)}")
    end
  end

  defp stream_logs(node_ref, level, save_path, format) do
    DalaDev.Output.step("Streaming logs (Ctrl+C to stop)")
    DalaDev.Output.info(String.duplicate("-", 80))

    stream = LogCollector.stream_logs(node_ref, level: level)

    if save_path do
      File.mkdir_p!(Path.dirname(save_path))

      File.open!(save_path, [:write, :utf8])
      |> then(fn file ->
        stream
        |> Stream.each(fn entry ->
          output = format_entry(entry, format)
          DalaDev.Output.info(output)
          IO.puts(file, output)
        end)
        |> Stream.run()

        File.close(file)
      end)
    else
      stream
      |> Stream.each(fn entry ->
        DalaDev.Output.info(format_entry(entry, format))
      end)
      |> Stream.run()
    end
  rescue
    e ->
      DalaDev.Output.error("Stream error: #{Exception.message(e)}")
  end

  defp display_logs(logs, :text) do
    Enum.each(logs, fn entry ->
      DalaDev.Output.info("[#{entry.ts}] #{entry.node} #{entry.level}: #{entry.message}")
    end)

    DalaDev.Output.info("Total: #{length(logs)} entries")
  end

  defp display_logs(logs, :jsonl) do
    Enum.each(logs, fn entry ->
      DalaDev.Output.info(Jason.encode!(entry))
    end)
  end

  defp display_logs(logs, :csv) do
    DalaDev.Output.info("ts,node,level,message,metadata")

    Enum.each(logs, fn entry ->
      meta = inspect(entry.metadata)
      DalaDev.Output.info("#{entry.ts},#{entry.node},#{entry.level},\"#{entry.message}\",\"#{meta}\"")
    end)
  end

  defp format_entry(entry, :text) do
    "[#{entry.ts}] #{entry.node} #{entry.level}: #{entry.message}"
  end

  defp format_entry(entry, :jsonl) do
    Jason.encode!(entry)
  end

  defp format_entry(entry, :csv) do
    meta = inspect(entry.metadata)
    "#{entry.ts},#{entry.node},#{entry.level},\"#{entry.message}\",\"#{meta}\""
  end
end
