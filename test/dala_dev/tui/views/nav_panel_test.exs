defmodule DalaDev.Tui.Views.NavPanelTest do
  use ExUnit.Case, async: true

  alias DalaDev.Tui.Devices
  alias DalaDev.Tui.Remote
  alias DalaDev.Tui.State
  alias DalaDev.Tui.Tasks
  alias DalaDev.Tui.Views.NavPanel
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.List

  @rect %Rect{x: 0, y: 0, width: 30, height: 20}

  defp android_device(opts \\ []) do
    %Devices{
      id: opts[:id] || "emulator-5554",
      platform: :android,
      type: :emulator,
      name: opts[:name] || "Pixel 8",
      status: opts[:status] || :connected,
      serial: "emulator-5554",
      node: opts[:node]
    }
  end

  test "render/2 returns a single list widget tuple" do
    state = State.new([android_device()], Tasks.list(), [])

    assert [{%List{items: items}, @rect}] = NavPanel.render(state, @rect)
    assert length(items) > 0
  end

  test "devices tab formats devices with status icon and node hint" do
    device = android_device(node: :"dala_demo_android@127.0.0.1")
    state = State.new([device], Tasks.list(), [])

    [{widget, _}] = NavPanel.render(state, @rect)
    text = inspect(widget.items)

    assert text =~ Devices.status_icon(device)
    assert text =~ "Pixel 8"
    assert text =~ "dala_demo_android@127.0.0.1"
  end

  test "devices tab omits node hint when device has no node" do
    state = State.new([android_device()], Tasks.list(), [])

    [{widget, _}] = NavPanel.render(state, @rect)
    text = inspect(widget.items)

    refute text =~ "→"
  end

  test "tasks tab shows category headers before their tasks" do
    tasks = Tasks.list()
    state = State.new([], tasks, [])
    state = %{state | current_tab: :tasks}

    [{widget, _}] = NavPanel.render(state, @rect)
    items = widget.items

    # Category rows come first and are prefixed with ◆
    category_rows = Enum.filter(items, &String.starts_with?(&1, "◆"))
    task_rows = Enum.filter(items, &String.starts_with?(&1, "  └"))

    assert length(category_rows) > 0
    assert length(task_rows) == length(tasks)

    # First item must be a category header, not a task
    assert hd(items) |> String.starts_with?("◆")
  end

  test "output tab renders an empty list with Output title" do
    state = State.new([], [], [])
    state = %{state | current_tab: :output}

    [{widget, _}] = NavPanel.render(state, @rect)

    assert widget.items == []
    assert inspect(widget.block.title) =~ "Output"
  end

  test "debug tab shows remote nodes with version and latency" do
    remote = %Remote{
      node: :"dala_demo_ios@127.0.0.1",
      version: "0.8.0",
      latency_ms: 12.3
    }

    state = State.new([], [], [remote])
    state = %{state | current_tab: :debug}

    [{widget, _}] = NavPanel.render(state, @rect)

    text = inspect(widget.items)
    assert text =~ "🟢"
    assert text =~ "v0.8.0"
    assert text =~ "12ms"
  end

  test "debug tab marks errored remotes with ❌" do
    remote = %Remote{node: :"down@127.0.0.1", error: :nodedown}
    state = State.new([], [], [remote])
    state = %{state | current_tab: :debug}

    [{widget, _}] = NavPanel.render(state, @rect)

    assert inspect(widget.items) =~ "❌"
  end

  test "nav_selected is clamped to the number of items" do
    state = State.new([android_device()], Tasks.list(), [])
    state = %{state | nav_selected: 99}

    [{widget, _}] = NavPanel.render(state, @rect)

    assert widget.selected == 0
  end

  test "selected is nil when there are no items" do
    state = State.new([], [], [])
    state = %{state | current_tab: :output}

    [{widget, _}] = NavPanel.render(state, @rect)

    assert widget.selected == nil
  end

  test "border style reflects nav focus" do
    focused = State.new([android_device()], Tasks.list(), [])
    unfocused = %{focused | focus: :detail}

    [{w_focused, _}] = NavPanel.render(focused, @rect)
    [{w_unfocused, _}] = NavPanel.render(unfocused, @rect)

    assert w_focused.block.border_style != w_unfocused.block.border_style
  end
end
