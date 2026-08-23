defmodule DalaDev.Tui.StateTest do
  use ExUnit.Case, async: true

  alias DalaDev.Tui.Devices
  alias DalaDev.Tui.Remote
  alias DalaDev.Tui.State
  alias DalaDev.Tui.Tasks

  describe "State.new/3" do
    test "creates state with devices, tasks, and remotes" do
      devices = sample_devices()
      tasks = Tasks.list()
      remotes = sample_remotes()

      state = State.new(devices, tasks, remotes)

      assert length(state.devices) == 2
      assert length(state.tasks) > 0
      assert length(state.remotes) == 1
      assert state.current_tab == :devices
      assert state.focus == :nav
      assert state.show_help == false
      assert state.loading == false
      assert state.refreshing == false
    end

    test "handles empty state" do
      state = State.new([], [], [])

      assert state.devices == []
      assert state.selected_device == nil
      assert state.selected_remote == nil
      assert state.remotes == []
    end

    test "sets first device and task as selected" do
      devices = sample_devices()
      tasks = Tasks.list()
      remotes = sample_remotes()

      state = State.new(devices, tasks, remotes)

      assert state.selected_device == hd(devices)
      assert state.selected_task == hd(tasks)
      assert state.selected_remote == hd(remotes)
    end
  end

  describe "nav_items/1" do
    test "returns device items when on devices tab" do
      state = State.new(sample_devices(), [], [])
      items = State.nav_items(state)

      assert length(items) == 2
      assert {:device, _} = hd(items)
    end

    test "returns task items when on tasks tab" do
      state = State.new([], Tasks.list())
      state = %{state | current_tab: :tasks}
      items = State.nav_items(state)

      assert length(items) > 0
    end

    test "returns remote items when on debug tab" do
      state = State.new([], [], sample_remotes())
      state = %{state | current_tab: :debug}
      items = State.nav_items(state)

      assert length(items) == 1
      assert {:remote, _} = hd(items)
    end

    test "returns empty when on output tab" do
      state = State.new([], [])
      state = %{state | current_tab: :output}
      items = State.nav_items(state)

      assert items == []
    end

    test "returns multiple remotes on debug tab" do
      remotes = sample_remotes() ++ [%Remote{node: :other@localhost, version: "0.7.0"}]
      state = State.new([], [], remotes)
      state = %{state | current_tab: :debug}
      items = State.nav_items(state)

      assert length(items) == 2
    end
  end

  describe "handle_key/2" do
    test "j moves selection down" do
      state = State.new(sample_devices(), [], [])
      state = State.handle_key(state, "j")
      assert state.nav_selected == 1
    end

    test "k moves selection up" do
      state = State.new(sample_devices(), [], [])
      state = State.handle_key(state, "j")
      state = State.handle_key(state, "k")
      assert state.nav_selected == 0
    end

    test "does not go below 0" do
      state = State.new(sample_devices(), [], [])
      state = State.handle_key(state, "k")
      assert state.nav_selected == 0
    end

    test "does not exceed max index" do
      state = State.new(sample_devices(), [], [])
      state = State.handle_key(state, "j")
      state = State.handle_key(state, "j")
      state = State.handle_key(state, "j")
      assert state.nav_selected == 1
    end

    test "? toggles help" do
      state = State.new(sample_devices(), [], [])
      state = State.handle_key(state, "?")
      assert state.show_help == true
    end

    test "any key closes help" do
      state = State.new(sample_devices(), [], [])
      state = %{state | show_help: true}
      state = State.handle_key(state, "j")
      assert state.show_help == false
    end

    test "tab switches to next tab" do
      state = State.new(sample_devices(), [], [])
      state = State.handle_key(state, "tab")
      assert state.current_tab == :tasks

      state = State.handle_key(state, "tab")
      assert state.current_tab == :output

      state = State.handle_key(state, "tab")
      assert state.current_tab == :debug

      state = State.handle_key(state, "tab")
      assert state.current_tab == :devices
    end

    test "number keys jump to tabs" do
      state = State.new(sample_devices(), [], [])
      state = State.handle_key(state, "2")
      assert state.current_tab == :tasks

      state = State.handle_key(state, "3")
      assert state.current_tab == :output

      state = State.handle_key(state, "4")
      assert state.current_tab == :debug

      state = State.handle_key(state, "1")
      assert state.current_tab == :devices
    end

    test "l focuses detail panel" do
      state = State.new(sample_devices(), [], [])
      state = State.handle_key(state, "l")
      assert state.focus == :detail
    end

    test "h focuses nav panel" do
      state = State.new(sample_devices(), [], [])
      state = State.handle_key(state, "l")
      state = State.handle_key(state, "h")
      assert state.focus == :nav
    end

    test "enter selects device" do
      state = State.new(sample_devices(), [], [])
      state = State.handle_key(state, "enter")
      assert %Devices{id: "device-1"} = state.selected_device
    end

    test "enter on tasks tab switches to output" do
      state = State.new([], Tasks.list())
      state = %{state | current_tab: :tasks}

      # Move selection onto an actual task (index 0 may be a category header)
      items = State.nav_items(state)

      task_idx =
        Enum.find_index(items, fn
          {:task, _} -> true
          _ -> false
        end)

      state = %{state | nav_selected: task_idx || 0}
      state = State.handle_key(state, "enter")
      assert state.current_tab == :output
    end

    test "enter on debug tab selects remote" do
      state = State.new([], [], sample_remotes())
      state = %{state | current_tab: :debug}
      state = State.handle_key(state, "enter")
      assert %Remote{node: :demo@localhost} = state.selected_remote
    end

    test "r sets refreshing flag" do
      state = State.new(sample_devices(), [], [])
      state = State.handle_key(state, "r")
      assert state.refreshing == true
    end

    test "d sets deploy status message" do
      state = State.new(sample_devices(), [], [])
      state = State.handle_key(state, "d")
      assert state.status_message =~ "Deploying"
    end

    test "d with no device shows error message" do
      state = State.new([], [], [])
      state = State.handle_key(state, "d")
      assert state.status_message =~ "No device selected"
    end

    test "s sets stream logs status message" do
      state = State.new(sample_devices(), [], [])
      state = State.handle_key(state, "s")
      assert state.status_message =~ "Streaming logs"
    end

    test "s with no device shows error message" do
      state = State.new([], [], [])
      state = State.handle_key(state, "s")
      assert state.status_message =~ "No device selected"
    end

    test "i sets inspect status message" do
      state = State.new([], [], sample_remotes())
      state = %{state | current_tab: :debug, selected_remote: hd(sample_remotes())}
      state = State.handle_key(state, "i")
      assert state.status_message =~ "Inspecting"
      assert state.loading == true
    end

    test "i with no remote shows error message" do
      state = State.new([], [], [])
      state = %{state | current_tab: :debug}
      state = State.handle_key(state, "i")
      assert state.status_message =~ "No remote node selected"
    end

    test "unknown key does not change state" do
      state = State.new(sample_devices(), [], [])
      original_state = state
      state = State.handle_key(state, "x")
      assert state == original_state
    end
  end

  describe "breadcrumb/1" do
    test "returns device breadcrumb" do
      state = State.new(sample_devices(), [], [])
      assert State.breadcrumb(state) =~ "Devices"
    end

    test "returns task breadcrumb" do
      state = State.new([], Tasks.list())
      state = %{state | current_tab: :tasks}
      assert State.breadcrumb(state) =~ "Tasks"
    end

    test "returns output breadcrumb" do
      state = State.new([], [])
      state = %{state | current_tab: :output}
      assert State.breadcrumb(state) == "Output"
    end

    test "returns debug breadcrumb" do
      state = State.new([], [], sample_remotes())
      state = %{state | current_tab: :debug}
      assert State.breadcrumb(state) =~ "Debug"
    end

    test "includes device name in breadcrumb" do
      state = State.new(sample_devices(), [], [])
      assert State.breadcrumb(state) =~ "Pixel 7"
    end

    test "includes remote node in breadcrumb" do
      state = State.new([], [], sample_remotes())
      state = %{state | current_tab: :debug, selected_remote: hd(sample_remotes())}
      assert State.breadcrumb(state) =~ "demo@localhost"
    end
  end

  describe "detail_items/1" do
    test "returns device detail lines" do
      state = State.new(sample_devices(), [], [])
      items = State.detail_items(state)
      assert length(items) > 0
      assert hd(items) =~ "Pixel 7"
    end

    test "returns remote detail lines" do
      state = State.new([], [], sample_remotes())
      state = %{state | current_tab: :debug, selected_remote: hd(sample_remotes())}
      items = State.detail_items(state)
      assert length(items) > 0
    end

    test "returns empty for no device" do
      state = State.new([], [], [])
      assert State.detail_items(state) == []
    end

    test "returns empty for no remote" do
      state = State.new([], [], [])
      state = %{state | current_tab: :debug}
      assert State.detail_items(state) == []
    end

    test "returns output text" do
      state = State.new([], [])
      state = %{state | current_tab: :output, last_run_output: "Test output"}
      items = State.detail_items(state)
      assert items == ["Test output"]
    end

    test "returns placeholder for empty output" do
      state = State.new([], [])
      state = %{state | current_tab: :output}
      items = State.detail_items(state)
      assert items == ["No output yet. Run a task to see results here."]
    end
  end

  describe "device_detail/1 (tested via detail_items)" do
    test "includes platform info" do
      state = State.new(sample_devices(), [], [])
      items = State.detail_items(state)
      assert Enum.any?(items, &String.contains?(&1, "Platform"))
    end

    test "includes node info when connected" do
      device = %Devices{
        id: "1",
        platform: :android,
        type: :device,
        name: "Pixel 7",
        status: :connected,
        serial: "ABC",
        version: "14",
        node: :demo@localhost
      }

      state = State.new([device], [], [])
      items = State.detail_items(state)
      assert Enum.any?(items, &String.contains?(&1, "demo@localhost"))
    end

    test "shows not connected when no node" do
      state = State.new(sample_devices(), [], [])
      items = State.detail_items(state)
      assert Enum.any?(items, &String.contains?(&1, "not connected"))
    end

    test "includes dist port when available" do
      device = %Devices{
        id: "1",
        platform: :android,
        type: :device,
        name: "Pixel 7",
        status: :connected,
        serial: "ABC",
        version: "14",
        dist_port: 9100
      }

      state = State.new([device], [], [])
      items = State.detail_items(state)
      assert Enum.any?(items, &String.contains?(&1, "9100"))
    end
  end

  describe "remote_detail/1 (tested via detail_items)" do
    test "includes version info" do
      state = State.new([], [], sample_remotes())
      state = %{state | current_tab: :debug, selected_remote: hd(sample_remotes())}
      items = State.detail_items(state)
      assert Enum.any?(items, &String.contains?(&1, "0.8.0"))
      assert Enum.any?(items, &String.contains?(&1, "27"))
    end

    test "includes latency when available" do
      state = State.new([], [], sample_remotes())
      state = %{state | current_tab: :debug, selected_remote: hd(sample_remotes())}
      items = State.detail_items(state)
      assert Enum.any?(items, &String.contains?(&1, "ms"))
    end

    test "includes process count" do
      state = State.new([], [], sample_remotes())
      state = %{state | current_tab: :debug, selected_remote: hd(sample_remotes())}
      items = State.detail_items(state)
      assert Enum.any?(items, &String.contains?(&1, "150"))
    end

    test "shows N/A for missing version" do
      remote = %Remote{node: :test@localhost}
      state = State.new([], [], [remote])
      state = %{state | current_tab: :debug, selected_remote: remote}
      items = State.detail_items(state)
      assert Enum.any?(items, &String.contains?(&1, "N/A"))
    end

    test "includes screen info when available" do
      remote = %Remote{
        node: :test@localhost,
        version: "0.8.0",
        current_screen: "HomeScreen"
      }

      state = State.new([], [], [remote])
      state = %{state | current_tab: :debug, selected_remote: remote}
      items = State.detail_items(state)
      assert Enum.any?(items, &String.contains?(&1, "HomeScreen"))
    end

    test "includes assigns when available" do
      remote = %Remote{
        node: :test@localhost,
        version: "0.8.0",
        assigns: %{user: "John", theme: "dark"}
      }

      state = State.new([], [], [remote])
      state = %{state | current_tab: :debug, selected_remote: remote}
      items = State.detail_items(state)
      assert Enum.any?(items, &String.contains?(&1, "Assigns"))
      assert Enum.any?(items, &String.contains?(&1, "user"))
    end

    test "includes memory when available" do
      remote = %Remote{
        node: :test@localhost,
        version: "0.8.0",
        memory: %{total: 50_000_000, processes: 12_000_000}
      }

      state = State.new([], [], [remote])
      state = %{state | current_tab: :debug, selected_remote: remote}
      items = State.detail_items(state)
      assert Enum.any?(items, &String.contains?(&1, "Memory"))
      assert Enum.any?(items, &String.contains?(&1, "MB"))
    end
  end

  describe "format_bytes/1" do
    test "formats memory values in the remote detail view" do
      remote = %Remote{
        node: :test@localhost,
        version: "0.8.0",
        memory: %{total: 50_000_000, processes: 12_000_000}
      }

      state = State.new([], [], [remote])
      state = %{state | current_tab: :debug, selected_remote: remote}
      items = State.detail_items(state)

      assert Enum.any?(items, &String.contains?(&1, "50.0 MB"))
      assert Enum.any?(items, &String.contains?(&1, "12.0 MB"))
    end
  end

  describe "move_selection in detail panel" do
    test "j in detail panel moves detail selection" do
      state = State.new(sample_devices(), [], [])
      state = %{state | focus: :detail}
      state = State.handle_key(state, "j")
      assert state.detail_selected == 1
    end

    test "k in detail panel moves detail selection up" do
      state = State.new(sample_devices(), [], [])
      state = %{state | focus: :detail}
      state = State.handle_key(state, "j")
      state = State.handle_key(state, "k")
      assert state.detail_selected == 0
    end
  end

  describe "tab switching resets selection" do
    test "tab resets nav_selected to 0" do
      state = State.new(sample_devices(), [], [])
      state = %{state | nav_selected: 1}
      state = State.handle_key(state, "tab")
      assert state.nav_selected == 0
    end

    test "number key resets nav_selected to 0" do
      state = State.new(sample_devices(), [], [])
      state = %{state | nav_selected: 1}
      state = State.handle_key(state, "2")
      assert state.nav_selected == 0
    end
  end

  # ── Fixtures ───────────────────────────────────────────────

  defp sample_devices do
    [
      %Devices{
        id: "device-1",
        platform: :android,
        type: :device,
        name: "Pixel 7",
        status: :connected,
        serial: "ABC123",
        version: "14",
        node: nil,
        dist_port: nil,
        host_ip: nil,
        error: nil
      },
      %Devices{
        id: "sim-1",
        platform: :ios,
        type: :simulator,
        name: "iPhone 15 Pro",
        status: :connected,
        serial: "XYZ789",
        version: "17.0",
        node: nil,
        dist_port: nil,
        host_ip: nil,
        error: nil
      }
    ]
  end

  defp sample_remotes do
    [
      %Remote{
        node: :demo@localhost,
        version: "0.8.0",
        otp_version: "27",
        erts_version: "15.0",
        app_version: "0.1.0",
        current_screen: nil,
        screen_info: nil,
        assigns: nil,
        memory: nil,
        process_count: 150,
        supervision_tree: nil,
        latency_ms: 2.5,
        connected_at: nil,
        error: nil
      }
    ]
  end
end
