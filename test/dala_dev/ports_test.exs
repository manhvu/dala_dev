defmodule DalaDev.PortsTest do
  use ExUnit.Case, async: true

  alias DalaDev.Ports

  describe "liveview_port/0" do
    test "is deterministic and inside the documented range" do
      port = Ports.liveview_port()

      assert port == Ports.liveview_port()
      assert port in 4200..4999
      # Matches dala's hash-based allocation formula.
      app = Mix.Project.config()[:app] |> to_string()
      assert port == 4200 + rem(:erlang.phash2(app), 800)
    end
  end

  describe "listeners_on/1" do
    test "detects a process listening on a port we own" do
      {:ok, socket} = :gen_tcp.listen(0, [])

      # Find the OS-assigned port so the test never collides with anything.
      {:ok, port} =
        case :inet.sockname(socket) do
          {:ok, {_, p}} -> {:ok, p}
          other -> other
        end

      assert [pid] = Ports.listeners_on(port)
      assert pid == System.pid() |> String.to_integer()
      :gen_tcp.close(socket)

      # Closed sockets release the listener promptly on macOS.
      wait_until(fn -> Ports.listeners_on(port) == [] end)
    end

    test "returns empty for an almost-certainly-free high port" do
      assert Ports.listeners_on(0) == []
    end
  end

  describe "kill_pids/1" do
    test "returns 0 for an empty list and for nonexistent pids" do
      assert Ports.kill_pids([]) == 0
      assert Ports.kill_pids([9_999_999_999]) == 0
    end
  end

  describe "port_map/1 with injected devices" do
    @android %DalaDev.Device{platform: :android, serial: "emulator-5554", type: :emulator}
    @sim %DalaDev.Device{platform: :ios, serial: "AAAACCCC-DDDD", type: :simulator}

    test "epmd entry appears once; dist and LV entries per device" do
      entries = Ports.port_map(fn -> [@android, @sim] end)

      assert %{kind: :epmd, port: 4369} = Enum.find(entries, &(&1.kind == :epmd))
      assert Enum.count(entries, &(&1.kind == :epmd)) == 1

      dist = Enum.filter(entries, &(&1.kind == :dist))
      assert [%{port: 9100, device: "emulator-5554"}, %{port: 9101}] = dist

      lv = Enum.filter(entries, &(&1.kind == :liveview))
      assert length(lv) == 2
      assert Enum.all?(lv, fn e -> e.port == Ports.liveview_port() end)

      # ids/nodes are filled for filtering and display
      assert Enum.all?(Enum.reject(entries, &(&1.id == nil)), &is_binary(&1.id))
    end

    test "no devices means no entries at all (no phantom epmd row)" do
      assert [] = Ports.port_map(fn -> [] end)
    end
  end

  defp wait_until(fun, tries \\ 50)
  defp wait_until(_fun, 0), do: flunk("condition never became true")

  defp wait_until(fun, tries) do
    if fun.(), do: :ok, else: Process.sleep(20) && wait_until(fun, tries - 1)
  end
end
