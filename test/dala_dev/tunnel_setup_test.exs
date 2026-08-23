defmodule DalaDev.TunnelSetupTest do
  use ExUnit.Case, async: true

  alias DalaDev.Device
  alias DalaDev.Tunnel

  defp device(fields) do
    struct!(%Device{platform: :ios, serial: "test-serial"}, fields)
  end

  describe "setup/2 for iOS simulator" do
    test "assigns dist port by index and marks tunneled" do
      dev = device(type: :simulator, status: :discovered)

      assert {:ok, %Device{} = result} = Tunnel.setup(dev, 3)
      assert result.dist_port == 9103
      assert result.status == :tunneled
    end

    test "index 0 gets base port" do
      dev = device(type: :simulator)

      assert {:ok, %{dist_port: 9100}} = Tunnel.setup(dev, 0)
    end

    test "does not mutate host_ip or node" do
      dev = device(type: :simulator)

      assert {:ok, %{host_ip: nil, node: nil}} = Tunnel.setup(dev, 0)
    end
  end

  describe "setup/2 for physical iOS with known host_ip" do
    test "marks tunneled without changing dist_port" do
      dev = device(type: :physical, host_ip: "169.254.20.5", dist_port: 9107)

      assert {:ok, %{status: :tunneled, dist_port: 9107, host_ip: "169.254.20.5"}} =
               Tunnel.setup(dev, 0)
    end

    test "keeps existing node name" do
      dev = device(type: :physical, host_ip: "192.168.1.50", node: :"dala_demo_ios@192.168.1.50")

      assert {:ok, %{node: :"dala_demo_ios@192.168.1.50"}} = Tunnel.setup(dev, 2)
    end
  end

  describe "teardown/1" do
    test "iOS simulator teardown is a no-op returning :ok" do
      dev = device(type: :simulator, dist_port: 9100)
      assert Tunnel.teardown(dev) == :ok
    end

    test "physical iOS without dist_port returns :ok" do
      dev = device(type: :physical)
      assert Tunnel.teardown(dev) == :ok
    end
  end

  describe "setup/2 consistency with dist_port/1" do
    test "assigned port matches Tunnel.dist_port(index) across platforms" do
      for i <- 0..4 do
        sim = device(type: :simulator)
        assert {:ok, %{dist_port: port}} = Tunnel.setup(sim, i)
        assert port == Tunnel.dist_port(i)
      end
    end
  end
end
