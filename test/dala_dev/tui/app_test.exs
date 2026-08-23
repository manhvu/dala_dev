defmodule DalaDev.Tui.AppTest do
  use ExUnit.Case, async: true

  alias DalaDev.Tui.App

  describe "app lifecycle" do
    test "starts in test mode" do
      {:ok, pid} =
        App.start_link(
          state: DalaDev.Tui.State.new([], [], []),
          test_mode: {80, 24},
          name: nil
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "mounts with empty state" do
      {:ok, pid} =
        App.start_link(
          state: DalaDev.Tui.State.new([], [], []),
          test_mode: {80, 24},
          name: nil
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "mounts with pre-populated state" do
      devices = [
        %DalaDev.Tui.Devices{
          id: "test",
          platform: :android,
          type: :device,
          name: "Test Device",
          status: :connected,
          serial: "TEST123",
          version: "14"
        }
      ]

      state = DalaDev.Tui.State.new(devices, [], [])

      {:ok, pid} =
        App.start_link(
          state: state,
          test_mode: {80, 24},
          name: nil
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "handle_event" do
    test "q key stops the app" do
      state = DalaDev.Tui.State.new([], [], [])
      state_data = %{state: state, test_mode: nil, name: nil, show_help: false}

      result =
        App.handle_event(
          %ExRatatui.Event.Key{code: "q", kind: "press"},
          state_data
        )

      assert {:stop, _} = result
    end

    test "non-q key returns noreply" do
      state = DalaDev.Tui.State.new([], [], [])
      state_data = %{state: state, test_mode: nil, name: nil}

      result =
        App.handle_event(
          %ExRatatui.Event.Key{code: "j", kind: "press"},
          state_data
        )

      assert {:noreply, _} = result
    end

    test "unknown event returns noreply" do
      state = DalaDev.Tui.State.new([], [], [])
      state_data = %{state: state, test_mode: nil, name: nil}

      result = App.handle_event(%ExRatatui.Event.Mouse{}, state_data)

      assert {:noreply, ^state_data} = result
    end
  end

  describe "terminate" do
    test "returns ok" do
      assert App.terminate(:normal, %{}) == :ok
    end

    test "handles any reason" do
      assert App.terminate(:shutdown, %{}) == :ok
      assert App.terminate({:shutdown, :test}, %{}) == :ok
      assert App.terminate(:error, %{}) == :ok
    end
  end
end
