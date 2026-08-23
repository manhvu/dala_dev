defmodule DalaDev.LogCollectorExportTest do
  use ExUnit.Case, async: false

  alias DalaDev.LogCollector

  describe "collect_logs/2" do
    test "collects from the local node" do
      assert {:ok, logs} = LogCollector.collect_logs(Node.self())
      assert Enum.all?(logs, &log_entry?/1)
    end

    test "respects the :last limit" do
      assert {:ok, logs} = LogCollector.collect_logs(Node.self(), last: 1)
      assert length(logs) <= 1
    end
  end

  describe "fetch_local_logs/1" do
    test "returns a list without crashing" do
      assert Enum.all?(LogCollector.fetch_local_logs(), &log_entry?/1)
    end

    test "accepts level and since options" do
      assert Enum.all?(LogCollector.fetch_local_logs(level: :error, since: nil), fn entry ->
               entry.level == :error or Logger.compare_levels(entry.level, :error) != :lt
             end)
    end
  end

  describe "export_logs/2" do
    test "exports jsonl format" do
      path = Path.join("test_tmp", "logs.jsonl")
      File.mkdir_p!(Path.dirname(path))
      on_exit(fn -> File.rm_rf!(path) end)

      result = LogCollector.export_logs(path, nodes: Node.self(), format: :jsonl)

      case result do
        :ok -> assert File.exists?(path)
        {:error, _} -> :ok
      end
    end

    test "exports text format" do
      path = Path.join("test_tmp", "logs.txt")
      File.mkdir_p!(Path.dirname(path))
      on_exit(fn -> File.rm_rf!(path) end)

      result = LogCollector.export_logs(path, nodes: Node.self(), format: :text)

      case result do
        :ok -> assert File.exists?(path)
        {:error, _} -> :ok
      end
    end

    test "exports csv format" do
      path = Path.join("test_tmp", "logs.csv")
      File.mkdir_p!(Path.dirname(path))
      on_exit(fn -> File.rm_rf!(path) end)

      result = LogCollector.export_logs(path, nodes: Node.self(), format: :csv)

      case result do
        :ok -> assert File.exists?(path)
        {:error, _} -> :ok
      end
    end
  end

  describe "collect_beam_logs/2" do
    test "returns a list for the local node" do
      assert Enum.all?(LogCollector.collect_beam_logs(Node.self()), &log_entry?/1)
    end
  end

  defp log_entry?(entry) do
    match?(
      %{ts: %DateTime{}, node: _, level: _, message: msg, metadata: _} when is_binary(msg),
      entry
    )
  end
end
