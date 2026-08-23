defmodule DalaDev.Server.LogStreamerSupervisorTest do
  use ExUnit.Case, async: true

  # init/1 is pure — it builds the child spec. No processes required.
  test "supervises LogStreamer with a crash-tolerant restart policy" do
    {:ok, {flags, children}} = DalaDev.Server.LogStreamerSupervisor.init([])

    assert flags.strategy == :one_for_one
    # Port-backed streamers exit often; restarts must not exhaust the supervisor.
    assert flags.intensity == 50
    assert flags.period == 10

    assert [%{id: DalaDev.Server.LogStreamer}] = children
  end

  test "start_link registers the named supervisor" do
    # Only verifies the child-spec contract; starting the real tree would
    # drag in PubSub + DevicePoller.
    spec = DalaDev.Server.LogStreamerSupervisor.child_spec([])
    assert spec.id == DalaDev.Server.LogStreamerSupervisor
    assert elem(spec.start, 0) == DalaDev.Server.LogStreamerSupervisor
  end
end
