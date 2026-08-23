defmodule DalaDev.DebuggerTest do
  use ExUnit.Case, async: false

  alias DalaDev.Debugger

  describe "inspect_process_local/1" do
    test "returns error for non-existent process" do
      # Use a process that definitely doesn't exist;
      # We can't easily create a fake PID, so test with a dead process;
      pid = spawn(fn -> :ok end)
      # Give it time to die;
      Process.sleep(10)

      case Debugger.inspect_process_local(pid) do
        {:error, :process_not_found} -> :ok
        # Any error is fine;
        {:error, _} -> :ok
        other -> flunk("Expected error, got: #{inspect(other)}")
      end
    end
  end

  describe "eval_remote_local/2" do
    test "evaluates simple expression" do
      case Debugger.eval_remote_local("1 + 1", []) do
        {:ok, 2} -> :ok
        other -> flunk("Expected 2, got: #{inspect(other)}")
      end
    end

    test "evaluates Enum operation" do
      case Debugger.eval_remote_local("Enum.map(1..3, &(&1 * 2))", []) do
        {:ok, [2, 4, 6]} -> :ok
        other -> flunk("Expected [2, 4, 6], got: #{inspect(other)}")
      end
    end
  end

  describe "memory_report_local/0" do
    test "generates memory report" do
      local = Node.self()
      assert {:ok, report} = Debugger.memory_report_local()

      # Full documented shape: per-area formatted strings + raw keyword list
      assert %{
               node: ^local,
               total: _,
               processes: _,
               system: _,
               atom: _,
               binary: _,
               code: _,
               ets: _,
               raw: _
             } = report
    end
  end
end
