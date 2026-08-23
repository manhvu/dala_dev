defmodule DalaDev.TracingTest do
  use ExUnit.Case, async: false

  alias DalaDev.Tracing

  describe "start_trace/2" do
    test "returns a trace id for a single node" do
      assert {:ok, trace_id} = Tracing.start_trace(Node.self())
      assert is_reference(trace_id)
    end

    test "returns a trace id for a list of nodes" do
      assert {:ok, trace_id} = Tracing.start_trace([Node.self()])
      assert is_reference(trace_id)
    end

    test "accepts :all_nodes" do
      assert {:ok, _trace_id} = Tracing.start_trace(:all_nodes)
    end

    test "accepts options" do
      assert {:ok, _} =
               Tracing.start_trace(Node.self(), modules: [String], events: [:function_call])
    end
  end

  describe "stop_trace/1" do
    test "returns :ok" do
      {:ok, trace_id} = Tracing.start_trace(Node.self())
      assert :ok = Tracing.stop_trace(trace_id)
    end
  end

  describe "get_events/1" do
    test "returns a list" do
      {:ok, trace_id} = Tracing.start_trace(Node.self())
      assert [] = Tracing.get_events(trace_id)
    end
  end

  describe "export_chrome_trace/2" do
    test "writes a JSON file with traceEvents" do
      path = Path.join("test_tmp", "trace.json")
      File.mkdir_p!(Path.dirname(path))
      on_exit(fn -> File.rm_rf!(path) end)

      {:ok, trace_id} = Tracing.start_trace(Node.self())

      assert :ok = Tracing.export_chrome_trace(trace_id, path)

      content = File.read!(path)
      assert content =~ "traceEvents"
      assert content =~ "displayTimeUnit"

      File.rm(path)
    end

    test "returns error when path is not writable" do
      {:ok, trace_id} = Tracing.start_trace(Node.self())
      assert {:error, _} = Tracing.export_chrome_trace(trace_id, "/nonexistent/dir/t.json")
    end
  end

  describe "enable_trace_on_node/2" do
    test "returns :ok (runs on the remote node)" do
      assert :ok = Tracing.enable_trace_on_node(make_ref(), [])
    end
  end
end
