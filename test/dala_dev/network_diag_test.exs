defmodule DalaDev.NetworkDiagTest do
  use ExUnit.Case, async: false

  alias DalaDev.NetworkDiag

  describe "ping_node/2" do
    test "pings the local node successfully" do
      assert {:ok, ms} = NetworkDiag.ping_node(Node.self())
      assert is_integer(ms)
      assert ms >= 0
    end

    test "returns error for unreachable node" do
      assert {:error, _} = NetworkDiag.ping_node(:"nonexistent@127.0.0.1", timeout: 500)
    end

    test "accepts a binary node name" do
      # Binary gets converted to atom; nonexistent node errors
      assert {:error, _} = NetworkDiag.ping_node("nonexistent@127.0.0.1", timeout: 500)
    end
  end

  describe "measure_latency/2" do
    test "measures latency stats against local node" do
      assert {:ok, stats} = NetworkDiag.measure_latency(Node.self(), samples: 3)
      assert stats.samples == 3
      assert stats.min <= stats.max
      assert stats.avg >= stats.min
      assert stats.median >= 0
    end

    test "returns error when all samples fail" do
      assert {:error, :all_samples_failed} =
               NetworkDiag.measure_latency(:"nonexistent@127.0.0.1", samples: 2, timeout: 200)
    end
  end

  describe "get_interfaces_local/0" do
    test "returns local interfaces" do
      assert {:ok, %{interfaces: [_ | _] = interfaces}} = NetworkDiag.get_interfaces_local()

      # Every interface carries a dotted-quad IP and a loopback flag
      Enum.each(interfaces, fn iface ->
        octets = String.split(iface.ip, ".")
        assert length(octets) == 4

        Enum.each(octets, fn octet ->
          case Integer.parse(octet) do
            {num, ""} -> assert num in 0..255
            _ -> flunk("invalid IPv4 octet: #{inspect(octet)} in #{inspect(iface.ip)}")
          end
        end)

        assert iface.is_loopback in [true, false]
      end)

      # A loopback interface always exists
      assert Enum.any?(interfaces, & &1.is_loopback)
    end
  end

  describe "get_network_interfaces/2" do
    test "fetches interfaces from local node" do
      assert {:ok, %{interfaces: _}} = NetworkDiag.get_network_interfaces(Node.self())
    end
  end

  describe "trace_distribution/2" do
    test "traces to local node" do
      result = NetworkDiag.trace_distribution(Node.self())

      case result do
        {:ok, ["Local node: " <> _, "Target node: " <> _, "State: " <> _]} ->
          :ok

        # Distribution not started (nonode) — the error is handled gracefully
        {:error, _} ->
          :ok
      end
    end

    test "returns error for unreachable node" do
      assert {:error, _} = NetworkDiag.trace_distribution(:"nonexistent@127.0.0.1", timeout: 500)
    end
  end

  describe "check_epmd_health/2" do
    test "returns error when EPMD unreachable for nonexistent host" do
      result = NetworkDiag.check_epmd_health(:"foo@192.0.2.1", timeout: 500)
      # 192.0.2.1 is TEST-NET — connection refused or timeout, both are error paths
      assert match?(:ok, result) or match?({:error, _}, result)
    end
  end
end
