defmodule DalaDev.Tui.App do
  @moduledoc """
  Main TUI application using `ExRatatui.App` behaviour.

  Renders the two-panel layout and delegates key handling to `DalaDev.Tui.State`.
  """

  use ExRatatui.App

  alias DalaDev.Tui.Devices
  alias DalaDev.Tui.Remote
  alias DalaDev.Tui.State
  alias DalaDev.Tui.Tasks
  alias DalaDev.Tui.Theme
  alias DalaDev.Tui.Views.{DetailPanel, HelpOverlay, NavPanel, StatusBar}
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph
  alias ExRatatui.Widgets.Block

  # ── Callbacks ──────────────────────────────────────────────

  @impl true
  def mount(opts) do
    test_mode = Keyword.get(opts, :test_mode, nil)
    name = Keyword.get(opts, :name, nil)

    devices = Devices.list()
    tasks = Tasks.list()
    remotes = query_remotes()
    state = State.new(devices, tasks, remotes)

    {:ok, %{state: state, test_mode: test_mode, name: name}}
  end

  @impl true
  def render(%{state: state, test_mode: test_mode} = _state_data, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    if state.show_help do
      render_help(area)
    else
      render_dashboard(state, area, test_mode)
    end
  end

  @impl true
  def handle_event(
        %ExRatatui.Event.Key{code: "q", kind: "press"},
        %{show_help: false} = state_data
      ) do
    {:stop, state_data}
  end

  def handle_event(%ExRatatui.Event.Key{code: code, kind: "press"}, %{state: state} = state_data) do
    new_state = State.handle_key(state, code)

    # Handle side effects based on key presses
    new_state_data =
      case code do
        "r" ->
          # Refresh: re-query devices and remotes
          devices = Devices.list()
          remotes = query_remotes()
          new_state = %{new_state | devices: devices, remotes: remotes, refreshing: false}
          %{state_data | state: new_state}

        "i" ->
          # Inspect remote: query selected remote node
          case new_state.selected_remote do
            nil ->
              %{state_data | state: %{new_state | loading: false}}

            remote ->
              queried = Remote.query(remote.node)

              remotes =
                Enum.map(state_data.state.remotes, fn
                  %{node: node} when node == remote.node -> queried
                  r -> r
                end)

              new_state = %{
                new_state
                | selected_remote: queried,
                  remotes: remotes,
                  loading: false
              }

              %{state_data | state: new_state}
          end

        _ ->
          %{state_data | state: new_state}
      end

    {:noreply, new_state_data}
  end

  def handle_event(_event, state_data) do
    {:noreply, state_data}
  end

  @impl true
  def terminate(_reason, _state_data), do: :ok

  # ── Layout ─────────────────────────────────────────────────

  defp render_dashboard(state, area, _test_mode) do
    [header_area, body_area, status_area, footer_area] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:min, 0},
        {:length, 1},
        {:length, 3}
      ])

    [nav_area, detail_area] =
      Layout.split(body_area, :horizontal, [
        {:percentage, 30},
        {:percentage, 70}
      ])

    header_widgets = render_header(state, header_area)
    nav_widgets = NavPanel.render(state, nav_area)
    detail_widgets = DetailPanel.render(state, detail_area)
    status_widgets = StatusBar.render(state, status_area)
    footer_widgets = render_footer(state, footer_area)

    header_widgets ++ nav_widgets ++ detail_widgets ++ status_widgets ++ footer_widgets
  end

  defp render_header(state, rect) do
    [
      {%Paragraph{
         text: Theme.brand_title(State.breadcrumb(state)),
         block: %Block{
           borders: [:all],
           border_type: :rounded,
           border_style: Theme.focused_border_style()
         }
       }, rect}
    ]
  end

  defp render_footer(state, rect) do
    [
      {%Paragraph{
         text: footer_line(state),
         block: %Block{
           borders: [:all],
           border_type: :rounded,
           border_style: Theme.unfocused_border_style()
         }
       }, rect}
    ]
  end

  defp footer_line(%State{show_help: true}) do
    Theme.footer_line([
      {"any", "close help"},
      {"q", "quit"}
    ])
  end

  defp footer_line(%State{current_tab: :devices}) do
    Theme.footer_line([
      {"j/k", "navigate"},
      {"⏎", "select"},
      {"r", "refresh"},
      {"d", "deploy"},
      {"s", "stream logs"},
      {"Tab", "tabs"},
      {"?", "help"},
      {"q", "quit"}
    ])
  end

  defp footer_line(%State{current_tab: :tasks}) do
    Theme.footer_line([
      {"j/k", "navigate"},
      {"⏎", "run task"},
      {"Tab", "tabs"},
      {"?", "help"},
      {"q", "quit"}
    ])
  end

  defp footer_line(%State{current_tab: :debug}) do
    Theme.footer_line([
      {"j/k", "navigate"},
      {"⏎", "select"},
      {"i", "inspect node"},
      {"Tab", "tabs"},
      {"?", "help"},
      {"q", "quit"}
    ])
  end

  defp footer_line(_state) do
    Theme.footer_line([
      {"Tab", "tabs"},
      {"?", "help"},
      {"q", "quit"}
    ])
  end

  # ── Help Overlay ───────────────────────────────────────────

  defp render_help(area) do
    HelpOverlay.render(area)
  end

  # ── Remote Query ───────────────────────────────────────────

  defp query_remotes do
    Remote.connected_nodes()
    |> Enum.map(&Remote.query(&1))
  rescue
    _ -> []
  end
end
