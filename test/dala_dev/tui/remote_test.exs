defmodule DalaDev.Tui.RemoteTest do
  use ExUnit.Case, async: true

  alias DalaDev.Tui.Remote

  describe "struct defaults" do
    test "query/1 against an unreachable node leaves optional fields unset" do
      remote = Remote.query(:nonexistent@localhost)

      # Pattern-match (rather than field access) covers every optional field,
      # including the `assigns` field, without introspecting LiveView sockets.
      assert %Remote{
               node: :nonexistent@localhost,
               version: nil,
               otp_version: nil,
               erts_version: nil,
               app_version: nil,
               current_screen: nil,
               screen_info: nil,
               assigns: nil,
               memory: nil,
               process_count: 0,
               supervision_tree: nil,
               latency_ms: nil,
               connected_at: nil
             } = remote

      assert remote.error =~ "dala:"
    end

    test "query/1 against the local node fills in live values" do
      remote = Remote.query(Node.self())

      # system_info(:otp_release) returns a charlist, which the module inspects
      assert remote.otp_version == inspect(:erlang.system_info(:otp_release))
      assert remote.memory[:total] > 0
      assert remote.process_count > 0
      assert remote.latency_ms == nil or is_float(remote.latency_ms)
    end
  end

  describe "connected_nodes/0" do
    test "returns the VM's connected nodes as atoms" do
      nodes = Remote.connected_nodes()
      assert nodes == Node.list(:connected)
      assert Enum.all?(nodes, &is_atom/1)
    end
  end

  describe "reachable?/1" do
    test "returns false for unreachable node" do
      refute Remote.reachable?(:nonexistent@localhost)
    end

    test "returns false for invalid node name" do
      refute Remote.reachable?(:not_a_node)
    end
  end

  describe "get_dala_version/1" do
    test "returns error for unreachable node" do
      assert {:error, _} = Remote.get_dala_version(:nonexistent@localhost)
    end
  end

  describe "get_app_version/1" do
    test "returns error for unreachable node" do
      assert {:error, _} = Remote.get_app_version(:nonexistent@localhost)
    end
  end

  describe "get_screen_info/1" do
    test "returns error for unreachable node" do
      assert {:error, _} = Remote.get_screen_info(:nonexistent@localhost)
    end
  end

  describe "get_current_screen/1" do
    test "returns error for unreachable node" do
      assert {:error, _} = Remote.get_current_screen(:nonexistent@localhost)
    end
  end

  describe "get_assigns/1" do
    test "returns error for unreachable node" do
      assert {:error, _} = Remote.get_assigns(:nonexistent@localhost)
    end
  end

  describe "get_memory/1" do
    test "returns error for unreachable node" do
      assert {:error, _} = Remote.get_memory(:nonexistent@localhost)
    end
  end

  describe "get_process_count/1" do
    test "returns 0 for unreachable node" do
      assert Remote.get_process_count(:nonexistent@localhost) == 0
    end
  end

  describe "measure_latency/1" do
    test "returns error for unreachable node" do
      assert {:error, _} = Remote.measure_latency(:nonexistent@localhost)
    end
  end

  describe "eval/2" do
    test "returns error for unreachable node" do
      assert {:error, _} = Remote.eval(:nonexistent@localhost, "1 + 1")
    end
  end
end
