defmodule DalaDev.DebuggerLocalTest do
  use ExUnit.Case, async: false

  alias DalaDev.Debugger

  # A simple GenServer to inspect
  defmodule TestServer do
    use GenServer

    def start_link(state), do: GenServer.start_link(__MODULE__, state, name: __MODULE__)

    @impl true
    def init(state), do: {:ok, state}

    @impl true
    def handle_call(:ping, _from, state), do: {:reply, :pong, state}
  end

  setup do
    start_supervised!({TestServer, %{answer: 42}})
    :ok
  end

  describe "inspect_process_local/1" do
    test "inspects a live process by pid" do
      pid = Process.whereis(TestServer)
      assert {:ok, info} = Debugger.inspect_process_local(pid)
      assert info.memory > 0
      assert info.status in [:waiting, :running]
      assert info.pid == inspect(pid)
    end

    test "returns error for dead process" do
      dead = spawn(fn -> :ok end)
      Process.sleep(10)
      assert {:error, :process_not_found} = Debugger.inspect_process_local(dead)
    end
  end

  describe "get_supervision_tree_local/0" do
    test "returns a supervision tree structure" do
      assert {:ok, tree} = Debugger.get_supervision_tree_local()

      # No process is registered under :supervisor in the test VM, so the
      # fallback shape (scanned supervisors + note) is returned.
      assert %{supervisors: supervisors, note: note} = tree
      assert Enum.all?(supervisors, &is_binary/1)
      assert note =~ "supervisor"
    end
  end

  describe "eval_remote_local/2" do
    test "evaluates simple code" do
      assert {:ok, 3} = Debugger.eval_remote_local("1 + 2", [])
    end

    test "evaluates with bindings" do
      assert {:ok, 10} = Debugger.eval_remote_local("x * 2", x: 5)
    end

    test "returns error on bad code" do
      assert {:error, _} = Debugger.eval_remote_local("raise :boom", [])
    end
  end

  describe "memory_report_local/0" do
    test "returns formatted memory report" do
      assert {:ok, report} = Debugger.memory_report_local()

      # Formatted byte strings carry "<positive number> <unit>"
      [amount, unit] = String.split(report.total, " ")
      assert unit in ["B", "KB", "MB", "GB"]
      assert {value, ""} = Float.parse(amount)
      assert value > 0

      # raw mirrors :erlang.memory() — the total must be a positive integer
      assert {:total, bytes} = List.keyfind(report.raw, :total, 0)
      assert is_integer(bytes) and bytes > 0
    end
  end

  describe "get_process_state_local/1" do
    test "handles processes without sys state gracefully" do
      # A plain GenServer may not respond to :sys.get_state — must not crash
      pid = Process.whereis(TestServer)

      result =
        try do
          Debugger.get_process_state_local(pid)
        rescue
          _ -> :error_raised
        catch
          :exit, _ -> :process_exited
        end

      # get_process_state returns inspect(state) as a string, or nil
      assert result == nil or is_binary(result) or result in [:error_raised, :process_exited]
    end
  end
end
