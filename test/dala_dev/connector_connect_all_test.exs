defmodule DalaDev.ConnectorConnectAllTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias DalaDev.Connector

  describe "connect_all/1 — no devices" do
    @tag :slow_discovery
    test "returns empty lists and prints hints when nothing connected" do
      {connected, failed} = Connector.connect_all(device: "DEFINITELY_NOT_A_DEVICE")
      assert connected == []
      assert failed == []
    end

    @tag :slow_discovery
    test "prints device hints when no devices found" do
      output =
        capture_io(fn ->
          Connector.connect_all(device: "DEFINITELY_NOT_A_DEVICE")
        end)

      assert output =~ "No devices" or output =~ "Scanning"
    end
  end
end
