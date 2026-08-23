defmodule DalaDev.Tui.Views.NavPanel do
  @moduledoc """
  Left panel view: navigation list showing devices, tasks, remote nodes, or categories.

  Pure function — takes state and rect, returns `[{widget, rect}]`.
  """

  alias DalaDev.Tui.Devices
  alias DalaDev.Tui.Remote
  alias DalaDev.Tui.State
  alias DalaDev.Tui.Theme
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.{Block, List}

  @doc """
  Renders the navigation panel.

  Returns a list of `{widget, rect}` tuples.
  """
  @spec render(State.t(), Rect.t()) :: [{struct(), Rect.t()}]
  def render(state, rect) do
    items = State.nav_items(state)

    list_items =
      Enum.map(items, fn
        {:device, device} -> format_device(device)
        {:task, task} -> format_task(task)
        {:category, label, _tasks} -> format_category(label)
        {:remote, remote} -> format_remote(remote)
      end)

    selected = clamp_selected(state.nav_selected, length(list_items))

    nav_list = %List{
      items: list_items,
      selected: selected,
      highlight_style: Theme.highlight_style(),
      highlight_symbol: "▶ ",
      block: %Block{
        title: nav_title(state),
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(state.focus == :nav)
      }
    }

    [{nav_list, rect}]
  end

  # ── Private ──────────────────────────────────────────────────

  defp format_device(%Devices{} = device) do
    icon = Devices.status_icon(device)
    name = Devices.display_name(device)
    node_hint = if device.node, do: " → #{device.node}", else: ""
    "#{icon} #{name}#{node_hint}"
  end

  defp format_task(task) do
    "  └ #{task.name}"
  end

  defp format_category(label) do
    "◆ #{label}"
  end

  defp format_remote(%Remote{} = remote) do
    status = if remote.error, do: "❌", else: "🟢"
    version = if remote.version, do: " v#{remote.version}", else: ""
    latency =
      if remote.latency_ms, do: " (#{remote.latency_ms |> Float.round(0) |> trunc()}ms)", else: ""
    "#{status} #{remote.node}#{version}#{latency}"
  end

  defp nav_title(%State{current_tab: :devices, devices: devices}) do
    %Line{
      spans: [
        %Span{content: " Devices ", style: %Style{fg: Theme.cornflower(), modifiers: [:bold]}},
        %Span{
          content: to_string(length(devices)),
          style: %Style{fg: Theme.gold(), modifiers: [:bold]}
        },
        %Span{content: " found", style: Theme.dim_text_style()}
      ]
    }
  end

  defp nav_title(%State{current_tab: :tasks, tasks: tasks}) do
    %Line{
      spans: [
        %Span{content: " Tasks ", style: %Style{fg: Theme.cornflower(), modifiers: [:bold]}},
        %Span{
          content: to_string(length(tasks)),
          style: %Style{fg: Theme.gold(), modifiers: [:bold]}
        },
        %Span{content: " available", style: Theme.dim_text_style()}
      ]
    }
  end

  defp nav_title(%State{current_tab: :output}) do
    %Line{
      spans: [
        %Span{content: " Output ", style: %Style{fg: Theme.cornflower(), modifiers: [:bold]}}
      ]
    }
  end

  defp nav_title(%State{current_tab: :debug, remotes: remotes}) do
    connected = Enum.count(remotes, &(&1.error == nil))

    %Line{
      spans: [
        %Span{content: " Debug ", style: %Style{fg: Theme.cornflower(), modifiers: [:bold]}},
        %Span{
          content: "#{connected}/#{length(remotes)}",
          style: %Style{fg: Theme.gold(), modifiers: [:bold]}
        },
        %Span{content: " connected", style: Theme.dim_text_style()}
      ]
    }
  end

  defp clamp_selected(_index, 0), do: nil
  defp clamp_selected(index, count), do: min(index, count - 1)
end
