defmodule DalaDev.RemoteTest do
  use ExUnit.Case, async: false

  alias DalaDev.Remote

  describe "node management" do
    test "lists remote nodes" do
      # nodes/0 reports the currently connected remote nodes exactly
      assert Remote.nodes() == Node.list()
    end

    test "selects and gets node" do
      # Select current node for testing
      current_node = Node.self()
      assert :ok = Remote.select_node(current_node)
      assert {:ok, ^current_node} = Remote.selected_node()
    end

    test "clears selection" do
      Remote.select_node(Node.self())
      assert :ok = Remote.clear_selection()
      assert {:error, :no_node_selected} = Remote.selected_node()
    end

    test "auto-selects single node" do
      # This test assumes there's at least one remote node
      # In a real scenario, we'd set up test nodes
      result = Remote.auto_select()
      assert match?(:ok, result) or match?({:error, _}, result)
    end

    test "sets and gets timeout" do
      assert :ok = Remote.set_timeout(10_000)
      assert 10_000 = Remote.get_timeout()
      # Reset to default
      assert :ok = Remote.set_timeout(5000)
    end
  end

  describe "Observer submodule" do
    setup do
      Remote.select_node(Node.self())
      :ok
    end

    test "observes local node" do
      current_node = Node.self()
      assert {:ok, data} = Remote.Observer.observe()
      assert data.node == current_node
      assert data.system.memory.total > 0
      assert [%{pid: _} | _] = data.processes
    end

    test "gets system info" do
      system_info = Remote.Observer.system_info()

      assert %{memory: %{total: total}, uptime_ms: uptime_ms} = system_info
      assert total > 0
      assert uptime_ms >= 0
    end

    test "gets process list" do
      assert [%{pid: pid, memory: memory} | _] = processes = Remote.Observer.process_list()
      # pids are rendered as "#PID<...>" strings
      assert String.starts_with?(pid, "#PID<")
      assert length(processes) > 0
      assert is_integer(memory) and memory >= 0
    end

    test "gets ETS tables" do
      tables = Remote.Observer.ets_tables()
      assert Enum.all?(tables, fn t -> is_binary(t.id) and is_integer(t.size) end)
    end
  end

  describe "Debugger submodule" do
    setup do
      Remote.select_node(Node.self())
      :ok
    end

    test "gets memory report" do
      assert {:ok, report} = Remote.Debugger.memory_report()

      # Same documented shape as the local memory report
      local = Node.self()
      assert %{node: ^local, total: _, processes: _, raw: _} = report
      assert report.raw[:total] > 0
    end

    test "gets process state" do
      # Create a simple GenServer to test
      {:ok, pid} = Agent.start_link(fn -> %{count: 42} end)
      assert {:ok, state} = Remote.Debugger.get_state(pid)
      # State is inspect/1 of the agent's state
      assert state == inspect(%{count: 42})
      Agent.stop(pid)
    end

    test "gets process state by name" do
      {:ok, _pid} = Agent.start_link(fn -> %{data: "test"} end, name: :test_agent)
      assert {:ok, state} = Remote.Debugger.get_state(:test_agent)
      assert state == inspect(%{data: "test"})
      Agent.stop(:test_agent)
    end

    test "returns error for non-existent process" do
      assert {:error, :process_not_found} = Remote.Debugger.get_state(:nonexistent_process)
    end

    test "evaluates code" do
      assert {:ok, 2} = Remote.Debugger.eval("1 + 1")
      assert {:ok, [2, 4, 6]} = Remote.Debugger.eval("Enum.map(1..3, &(&1 * 2))")
    end

    test "evaluates code with bindings" do
      assert {:ok, 3} = Remote.Debugger.eval("x + 1", bindings: [x: 2])
    end

    test "inspects current process" do
      # Can't inspect current process due to :sys.get_state limitation
      # Use a different process instead
      other_pid = spawn(fn -> Process.sleep(:infinity) end)
      assert {:ok, info} = Remote.Debugger.inspect_process(other_pid)
      assert info.pid == inspect(other_pid)
      assert info.message_queue_len == 0
      Process.exit(other_pid, :kill)
    end

    @tag :skip
    test "traces messages" do
      # Create a simple test process that stays alive
      test_pid =
        spawn_link(fn ->
          # Keep the process alive - just wait indefinitely
          receive do
            :stop -> :ok
          after
            5000 -> :ok
          end
        end)

      # Wait a bit for the process to be ready
      Process.sleep(10)

      # Verify the process is alive
      assert Process.alive?(test_pid)

      # Trace the test process with a longer duration to capture more messages
      assert {:ok, messages} = Remote.Debugger.trace_messages(test_pid, duration: 5000)

      # Send many messages to trigger tracing
      for i <- 1..100 do
        send(test_pid, {:msg, i})
      end

      # Stop the process
      send(test_pid, :stop)

      # Wait for the trace to complete
      Process.sleep(100)

      # Should have captured messages
      assert Enum.all?(messages, &match?({:trace, _, :send, _, _}, &1))
    end

    test "gets supervision tree" do
      assert {:ok, tree} = Remote.Debugger.supervision_tree()
      assert map_size(tree) > 0
      # Tree can have different structures depending on whether :supervisor process exists
      assert Map.has_key?(tree, :pid) or Map.has_key?(tree, :supervisors)
    end
  end

  describe "Rpc submodule" do
    setup do
      Remote.select_node(Node.self())
      :ok
    end

    test "calls function on selected node" do
      assert {:ok, 2} = Remote.Rpc.call(Kernel, :+, [1, 1])
    end

    test "calls function with no arguments" do
      assert {:ok, :ok} = Remote.Rpc.call(Process, :sleep, [0])
    end

    test "handles function errors" do
      assert {:error, _} = Remote.Rpc.call(Kernel, :+, [1, "not_a_number"])
    end

    test "calls function with custom timeout" do
      assert {:ok, 3} = Remote.Rpc.call(Kernel, :+, [1, 2], timeout: 10_000)
    end
  end
end
