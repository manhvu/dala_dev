defmodule DalaDev.Tui.RemoteExtraTest do
  use ExUnit.Case, async: true

  alias DalaDev.Tui.Remote

  describe "connected_nodes/0" do
    test "mirrors the VM's connected node list" do
      nodes = Remote.connected_nodes()
      assert nodes == Node.list(:connected)
      assert Enum.all?(nodes, &is_atom/1)
    end
  end

  describe "reachable?/1" do
    test "false for unreachable node" do
      refute Remote.reachable?(:"definitely_not_a_node@127.0.0.1")
    end
  end

  describe "query/1" do
    test "returns a struct for unreachable node without crashing" do
      remote = Remote.query(:"nonexistent@127.0.0.1")
      assert is_map(remote) or is_struct(remote)
    end
  end

  describe "get_memory/1" do
    test "handles unreachable node" do
      result = Remote.get_memory(:"nonexistent@127.0.0.1")
      assert match?({:error, _}, result) or is_map(result)
    end
  end

  describe "get_process_count/1" do
    test "handles unreachable node" do
      result = Remote.get_process_count(:"nonexistent@127.0.0.1")
      assert is_integer(result) or is_nil(result)
    end
  end

  describe "measure_latency/1" do
    test "handles unreachable node" do
      result = Remote.measure_latency(:"nonexistent@127.0.0.1")
      assert match?({:ok, _}, result) or match?({:error, _}, result) or is_nil(result)
    end
  end
end

defmodule Mix.Tasks.Dala.CacheFormatSizeTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Dala.Cache

  # format_size/1 in the cache task — exercised via the public dir_size path
  test "formats sizes across unit boundaries" do
    assert Cache.format_size(0) == "0 B"
    assert Cache.format_size(512) == "512 B"
    assert Cache.format_size(2048) == "2.0 KB"
    assert Cache.format_size(5 * 1024 * 1024) == "5.0 MB"
    assert Cache.format_size(2 * 1024 * 1024 * 1024) == "2.00 GB"
  end
end
