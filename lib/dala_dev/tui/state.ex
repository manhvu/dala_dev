defmodule DalaDev.Tui.State do
  @moduledoc """
  State struct and pure navigation logic for the dala_dev TUI.

  All state transitions are pure functions: `handle_key(state, key) -> state`.
  No side effects, no processes — just data transformation.
  """

  alias DalaDev.Tui.Devices
  alias DalaDev.Tui.Remote
  alias DalaDev.Tui.Tasks

  defstruct [
    :devices,
    :tasks,
    :remotes,
    :selected_device,
    :selected_task,
    :selected_remote,
    :current_tab,
    :nav_selected,
    :detail_selected,
    :focus,
    :show_help,
    :last_run_output,
    :refreshing,
    :loading,
    :status_message,
    :version_info
  ]

  @type t :: %__MODULE__{
          devices: [Devices.t()],
          tasks: [Tasks.t()],
          remotes: [Remote.t()],
          selected_device: Devices.t() | nil,
          selected_task: Tasks.t() | nil,
          selected_remote: Remote.t() | nil,
          current_tab: :devices | :tasks | :output | :debug,
          nav_selected: non_neg_integer(),
          detail_selected: non_neg_integer(),
          focus: :nav | :detail,
          show_help: boolean(),
          last_run_output: String.t() | nil,
          refreshing: boolean(),
          loading: boolean(),
          status_message: String.t() | nil,
          version_info: map() | nil
        }

  @tabs [:devices, :tasks, :output, :debug]

  @doc """
  Creates a new state with loaded devices, tasks, and remote info.
  """
  @spec new([Devices.t()], [Tasks.t()], [Remote.t()]) :: t()
  def new(devices \\ [], tasks \\ [], remotes \\ []) do
    %__MODULE__{
      devices: devices,
      tasks: tasks,
      remotes: remotes,
      selected_device: List.first(devices),
      selected_task: List.first(tasks),
      selected_remote: List.first(remotes),
      current_tab: :devices,
      nav_selected: 0,
      detail_selected: 0,
      focus: :nav,
      show_help: false,
      last_run_output: nil,
      refreshing: false,
      loading: false,
      status_message: nil,
      version_info: nil
    }
  end

  @doc """
  Returns the items shown in the navigation panel.
  """
  @spec nav_items(t()) :: [term()]
  def nav_items(%__MODULE__{current_tab: :devices, devices: devices}) do
    Enum.map(devices, &{:device, &1})
  end

  def nav_items(%__MODULE__{current_tab: :tasks, tasks: tasks}) do
    categories = Tasks.categories()

    Enum.flat_map(categories, fn {cat, label} ->
      cat_tasks = Enum.filter(tasks, &(&1.category == cat))

      if cat_tasks != [],
        do: [{:category, label, cat_tasks} | Enum.map(cat_tasks, &{:task, &1})],
        else: []
    end)
  end

  def nav_items(%__MODULE__{current_tab: :output}) do
    []
  end

  def nav_items(%__MODULE__{current_tab: :debug, remotes: remotes}) do
    Enum.map(remotes, &{:remote, &1})
  end

  @doc """
  Returns the items for the currently active detail tab.
  """
  @spec detail_items(t()) :: [term()]
  def detail_items(%__MODULE__{current_tab: :devices, selected_device: nil}), do: []

  def detail_items(%__MODULE__{current_tab: :devices, selected_device: device}) do
    device_detail(device)
  end

  def detail_items(%__MODULE__{current_tab: :tasks, selected_task: nil}), do: []

  def detail_items(%__MODULE__{current_tab: :tasks, selected_task: task}) do
    task_detail(task)
  end

  def detail_items(%__MODULE__{current_tab: :output, last_run_output: output}) do
    if output, do: [output], else: ["No output yet. Run a task to see results here."]
  end

  def detail_items(%__MODULE__{current_tab: :debug, selected_remote: nil}), do: []

  def detail_items(%__MODULE__{current_tab: :debug, selected_remote: remote}) do
    remote_detail(remote)
  end

  @doc """
  Returns the breadcrumb trail for the current view.
  """
  @spec breadcrumb(t()) :: String.t()
  def breadcrumb(%__MODULE__{current_tab: :devices, selected_device: device}) do
    if device, do: "Devices > #{device.name}", else: "Devices"
  end

  def breadcrumb(%__MODULE__{current_tab: :tasks, selected_task: task}) do
    if task, do: "Tasks > #{task.name}", else: "Tasks"
  end

  def breadcrumb(%__MODULE__{current_tab: :output}) do
    "Output"
  end

  def breadcrumb(%__MODULE__{current_tab: :debug, selected_remote: remote}) do
    if remote, do: "Debug > #{remote.node}", else: "Debug"
  end

  @doc """
  Processes a key press and returns the updated state.
  """
  @spec handle_key(t(), String.t()) :: t()
  def handle_key(%__MODULE__{show_help: true} = state, _key) do
    %{state | show_help: false}
  end

  def handle_key(state, "q") do
    %{state | show_help: false}
  end

  def handle_key(state, "?") do
    %{state | show_help: true}
  end

  def handle_key(state, key) when key in ["j", "down"] do
    move_selection(state, :down)
  end

  def handle_key(state, key) when key in ["k", "up"] do
    move_selection(state, :up)
  end

  def handle_key(state, "enter") do
    handle_enter(state)
  end

  def handle_key(state, "tab") do
    next_tab(state)
  end

  def handle_key(state, key) when key in ["1", "2", "3", "4"] do
    idx = String.to_integer(key) - 1
    tab = Enum.at(@tabs, idx, :devices)
    %{state | current_tab: tab, nav_selected: 0, detail_selected: 0}
  end

  def handle_key(state, key) when key in ["h", "left"] do
    %{state | focus: :nav}
  end

  def handle_key(state, key) when key in ["l", "right"] do
    %{state | focus: :detail}
  end

  def handle_key(state, "r") do
    %{state | refreshing: true}
  end

  def handle_key(state, "d") do
    # Deploy action — set status message
    case state.selected_device do
      nil -> %{state | status_message: "No device selected"}
      device -> %{state | status_message: "Deploying to #{device.name}..."}
    end
  end

  def handle_key(state, "s") do
    # Stream logs action
    case state.selected_device do
      nil -> %{state | status_message: "No device selected for log streaming"}
      device -> %{state | status_message: "Streaming logs from #{device.name}..."}
    end
  end

  def handle_key(state, "i") do
    # Inspect remote node
    case state.selected_remote do
      nil -> %{state | status_message: "No remote node selected"}
      remote -> %{state | status_message: "Inspecting #{remote.node}...", loading: true}
    end
  end

  def handle_key(state, _key), do: state

  # ── Private ──────────────────────────────────────────────────

  defp move_selection(%{focus: :nav} = state, direction) do
    items = nav_items(state)
    max_idx = max(length(items) - 1, 0)

    new_selected =
      case direction do
        :down -> min(state.nav_selected + 1, max_idx)
        :up -> max(state.nav_selected - 1, 0)
      end

    # Skip category header rows — they are not selectable actions
    new_selected = skip_category(items, new_selected, direction, max_idx)

    # Update selected item based on new position
    selected = Enum.at(items, new_selected)
    state = %{state | nav_selected: new_selected}

    case state.current_tab do
      :devices ->
        case selected do
          {:device, device} -> %{state | selected_device: device}
          _ -> state
        end

      :tasks ->
        case selected do
          {:task, task} -> %{state | selected_task: task}
          _ -> state
        end

      :debug ->
        case selected do
          {:remote, remote} -> %{state | selected_remote: remote}
          _ -> state
        end

      _ ->
        state
    end
  end

  defp move_selection(%{focus: :detail} = state, direction) do
    items = detail_items(state)
    max_idx = max(length(items) - 1, 0)

    new_selected =
      case direction do
        :down -> min(state.detail_selected + 1, max_idx)
        :up -> max(state.detail_selected - 1, 0)
      end

    %{state | detail_selected: new_selected}
  end

  defp skip_category(items, idx, direction, max_idx) do
    cond do
      idx > max_idx ->
        idx

      match?({:category, _, _}, Enum.at(items, idx)) and direction == :down and idx < max_idx ->
        skip_category(items, idx + 1, direction, max_idx)

      match?({:category, _, _}, Enum.at(items, idx)) and direction == :up and idx > 0 ->
        skip_category(items, idx - 1, direction, max_idx)

      true ->
        idx
    end
  end

  defp handle_enter(%{focus: :nav, current_tab: :devices} = state) do
    items = nav_items(state)

    case Enum.at(items, state.nav_selected) do
      {:device, device} -> %{state | selected_device: device, detail_selected: 0}
      _ -> state
    end
  end

  defp handle_enter(%{focus: :nav, current_tab: :tasks} = state) do
    items = nav_items(state)

    case Enum.at(items, state.nav_selected) do
      {:task, task} -> %{state | selected_task: task, detail_selected: 0, current_tab: :output}
      # Category headers are not selectable actions — no-op
      _ -> state
    end
  end

  defp handle_enter(%{focus: :nav, current_tab: :debug} = state) do
    items = nav_items(state)

    case Enum.at(items, state.nav_selected) do
      {:remote, remote} -> %{state | selected_remote: remote, detail_selected: 0}
      _ -> state
    end
  end

  defp handle_enter(state), do: state

  defp next_tab(state) do
    current_idx = Enum.find_index(@tabs, &(&1 == state.current_tab))
    next_idx = rem(current_idx + 1, length(@tabs))
    tab = Enum.at(@tabs, next_idx)
    %{state | current_tab: tab, nav_selected: 0, detail_selected: 0}
  end

  # ── Detail Builders ─────────────────────────────────────────

  @spec device_detail(Devices.t()) :: [String.t()]
  def device_detail(%Devices{} = device) do
    node_info =
      if device.node do
        "Node: #{device.node}"
      else
        "Node: not connected"
      end

    dist_info =
      if device.dist_port do
        "Dist Port: #{device.dist_port}"
      else
        "Dist Port: N/A"
      end

    [
      Devices.platform_icon(device) <> " " <> device.name,
      "",
      "Platform:  #{device.platform}",
      "Type:      #{device.type}",
      "Status:    #{Devices.status_label(device)}",
      "Serial:    #{device.serial || "N/A"}",
      "Version:   #{device.version || "N/A"}",
      node_info,
      dist_info,
      "",
      "Press d to deploy",
      "Press s to stream logs"
    ]
  end

  @spec task_detail(Tasks.t()) :: [String.t()]
  def task_detail(%Tasks{} = task) do
    [
      "mix dala.#{task.name}",
      "",
      "Category: #{task.category}",
      "",
      task.description,
      "",
      "Press Enter to run"
    ]
  end

  @spec remote_detail(Remote.t()) :: [String.t()]
  def remote_detail(%Remote{} = remote) do
    version_section = [
      "Node:    #{remote.node}",
      "Dala:    #{remote.version || "N/A"}",
      "OTP:     #{remote.otp_version || "N/A"}",
      "ERTS:    #{remote.erts_version || "N/A"}",
      "App:     #{remote.app_version || "N/A"}"
    ]

    connection_section =
      if remote.latency_ms do
        ["Latency: #{Float.round(remote.latency_ms, 1)}ms"]
      else
        ["Latency: measuring..."]
      end

    screen_section =
      if remote.current_screen do
        [
          "",
          "Screen: #{remote.current_screen}"
        ]
      else
        []
      end

    assigns_section =
      if is_map(remote.assigns) and map_size(remote.assigns) > 0 do
        [
          "",
          "Assigns:",
          Enum.map(remote.assigns, fn {k, v} -> "  #{k}: #{inspect(v)}" end)
        ]
        |> List.flatten()
      else
        []
      end

    memory_section =
      if is_map(remote.memory) and map_size(remote.memory) > 0 do
        [
          "",
          "Memory:",
          Enum.map(remote.memory, fn {k, v} -> "  #{k}: #{format_bytes(v)}" end)
        ]
        |> List.flatten()
      else
        []
      end

    process_section =
      if remote.process_count do
        ["Processes: #{remote.process_count}"]
      else
        []
      end

    version_section ++
      connection_section ++ screen_section ++ assigns_section ++ memory_section ++ process_section
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_000_000_000 -> "#{Float.round(bytes / 1_000_000_000, 1)} GB"
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_bytes(_), do: "N/A"
end
