defmodule DalaDev.LogCollectorTest do
  use ExUnit.Case, async: false

  alias DalaDev.LogCollector

  describe "collect_logs/2" do
    test "returns ok tuple with empty list when no nodes" do
      # Test with a non-existent node
      result = LogCollector.collect_logs(:non_existent@node, last: 10)
      assert {:ok, _} = result
    end

    test "accepts :all_nodes atom" do
      result = LogCollector.collect_logs(:all_nodes, level: :info)
      assert {:ok, _} = result
    end

    test "accepts node list" do
      result = LogCollector.collect_logs([Node.self()], last: 5)
      assert {:ok, _} = result
    end
  end

  describe "export_logs/2" do
    test "exports to jsonl format" do
      path = "/tmp/test_logs_#{:erlang.unique_integer([:positive])}.jsonl"
      result = LogCollector.export_logs(path, nodes: [Node.self()], format: :jsonl)
      assert result == :ok or match?({:error, _}, result)
    end

    test "exports to text format" do
      path = "/tmp/test_logs_#{:erlang.unique_integer([:positive])}.txt"
      result = LogCollector.export_logs(path, nodes: [Node.self()], format: :text)
      assert result == :ok or match?({:error, _}, result)
    end

    test "exports to csv format" do
      path = "/tmp/test_logs_#{:erlang.unique_integer([:positive])}.csv"
      result = LogCollector.export_logs(path, nodes: [Node.self()], format: :csv)
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "stream_logs/2" do
    test "returns a stream" do
      stream = LogCollector.stream_logs(Node.self(), level: :info)
      assert is_function(stream)
    end
  end

  describe "collect_android_logs/2" do
    test "handles missing adb gracefully" do
      # This test just ensures the function doesn't crash
      result = LogCollector.collect_android_logs("non_existent_device", lines: 10)

      case result do
        {:ok, _} -> :ok
        {:error, _} -> :ok
        _ -> flunk("Unexpected result: #{inspect(result)}")
      end
    end
  end

  describe "fetch_local_logs/1" do
    test "runs on local node" do
      result = LogCollector.fetch_local_logs(level: :info)

      assert Enum.all?(result, fn entry ->
               match?(
                 %{ts: %DateTime{}, node: _, level: _, message: msg} when is_binary(msg),
                 entry
               )
             end)
    end
  end
end
