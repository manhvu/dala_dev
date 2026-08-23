defmodule DalaDev.Tui.Views.DetailPanelTest do
  use ExUnit.Case, async: true

  alias DalaDev.Tui.Devices
  alias DalaDev.Tui.Remote
  alias DalaDev.Tui.State
  alias DalaDev.Tui.Tasks
  alias DalaDev.Tui.Views.DetailPanel
  alias ExRatatui.Layout.Rect

  @rect %Rect{x: 0, y: 0, width: 50, height: 24}

  defp device do
    %Devices{
      id: "emulator-5554",
      platform: :android,
      type: :emulator,
      name: "Pixel 8",
      status: :connected,
      serial: "emulator-5554"
    }
  end

  defp render_text(state) do
    [{widget, _}] = DetailPanel.render(state, @rect)
    inspect(widget.text)
  end

  describe "devices tab" do
    test "shows placeholder when no device is selected" do
      state = State.new([], Tasks.list(), [])

      assert render_text(state) =~ "No device selected"
    end

    test "shows device detail lines for the selected device" do
      state = State.new([device()], Tasks.list(), [])

      text = render_text(state)
      assert text =~ "Pixel 8"
    end
  end

  describe "tasks tab" do
    test "shows placeholder when no task is selected" do
      state = State.new([], [], [])
      state = %{state | current_tab: :tasks}

      assert render_text(state) =~ "No task selected"
    end

    test "shows task detail lines for the selected task" do
      tasks = Tasks.list()
      state = State.new([], tasks, [])
      state = %{state | current_tab: :tasks}

      text = render_text(state)
      assert text =~ hd(tasks).name
    end
  end

  describe "output tab" do
    test "shows placeholder when there is no output" do
      state = State.new([], [], [])
      state = %{state | current_tab: :output}

      assert render_text(state) =~ "No output yet"
    end

    test "shows the last run output" do
      state = State.new([], [], [])
      state = state |> struct(current_tab: :output, last_run_output: "build succeeded")

      assert render_text(state) =~ "build succeeded"
    end
  end

  describe "debug tab" do
    test "shows placeholder when no remote is selected" do
      state = State.new([], [], [])
      state = %{state | current_tab: :debug}

      assert render_text(state) =~ "No remote node selected"
    end

    test "shows loading message while a remote query is in flight" do
      remote = %Remote{node: :"dala_demo_ios@127.0.0.1"}
      state = State.new([], [], [remote])
      state = state |> struct(current_tab: :debug, loading: true)

      text = render_text(state)
      assert text =~ "Loading remote node info..."
      assert text =~ "Querying dala_demo_ios@127.0.0.1..."
    end

    test "shows remote detail when loaded" do
      remote = %Remote{
        node: :"dala_demo_ios@127.0.0.1",
        version: "1.2.3",
        process_count: 42
      }

      state = State.new([], [], [remote])
      state = %{state | current_tab: :debug}

      text = render_text(state)
      assert text =~ "dala_demo_ios@127.0.0.1"
      assert text =~ "1.2.3"
    end
  end
end
