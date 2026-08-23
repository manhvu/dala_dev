defmodule DalaDev.ClusterVizTest do
  use ExUnit.Case, async: false

  alias DalaDev.ClusterViz

  describe "topology/0" do
    test "returns topology with at least the local node" do
      assert {:ok, topo} = ClusterViz.topology()
      assert [%{node: node} | _] = topo.nodes
      assert node == Node.self()
      assert %DateTime{} = topo.timestamp

      # Every connection is an edge between known nodes
      known_nodes = [Node.self() | Node.list(:connected)]

      Enum.each(topo.connections, fn {from, to} ->
        assert from in known_nodes and to in known_nodes and from != to
      end)
    end
  end

  describe "health_dashboard/0" do
    test "returns health data for the local node" do
      assert {:ok, dashboard} = ClusterViz.health_dashboard()
      assert [%{node: node} | _] = dashboard.nodes
      assert node == Node.self()
      assert %DateTime{} = dashboard.timestamp
    end
  end

  describe "process_distribution/0" do
    test "returns a map (may be empty if supervision tree unavailable)" do
      assert {:ok, dist} = ClusterViz.process_distribution()
      assert %DateTime{} = dist.timestamp

      # The local node always contributes an entry carrying its tree
      local = Node.self()
      assert %{^local => _} = Map.new(dist.nodes, fn entry -> {entry.node, entry.tree} end)
    end
  end

  describe "liveview_flow/0" do
    test "returns empty flows" do
      assert {:ok, flow} = ClusterViz.liveview_flow()
      assert flow.flows == []
      assert %DateTime{} = flow.timestamp
    end
  end
end
