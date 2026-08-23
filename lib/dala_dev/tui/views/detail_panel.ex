defmodule DalaDev.Tui.Views.DetailPanel do
  @moduledoc """
  Right panel view: detail display for selected device, task, remote node, or output.

  Pure function — takes state and rect, returns `[{widget, rect}]`.
  """

  alias DalaDev.Tui.State
  alias DalaDev.Tui.Theme
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.{Block, Paragraph}

  @doc """
  Renders the detail panel content.

  Returns a list of `{widget, rect}` tuples.
  """
  @spec render(State.t(), Rect.t()) :: [{struct(), Rect.t()}]
  def render(state, rect) do
    case state.current_tab do
      :devices -> render_device_detail(state, rect)
      :tasks -> render_task_detail(state, rect)
      :output -> render_output(state, rect)
      :debug -> render_debug_detail(state, rect)
    end
  end

  # ── Device Detail ───────────────────────────────────────────

  defp render_device_detail(%State{selected_device: nil}, rect) do
    [
      {%Paragraph{
         text: "No device selected",
         block: %Block{
           borders: [:all],
           border_type: :rounded,
           border_style: Theme.unfocused_border_style()
         }
       }, rect}
    ]
  end

  defp render_device_detail(%State{selected_device: device}, rect) do
    lines =
      device
      |> DalaDev.Tui.State.device_detail()
      |> Enum.map(&to_line/1)

    [
      {%Paragraph{
         text: lines,
         block: %Block{
           borders: [:all],
           border_type: :rounded,
           border_style: Theme.unfocused_border_style()
         }
       }, rect}
    ]
  end

  # ── Task Detail ─────────────────────────────────────────────

  defp render_task_detail(%State{selected_task: nil}, rect) do
    [
      {%Paragraph{
         text: "No task selected",
         block: %Block{
           borders: [:all],
           border_type: :rounded,
           border_style: Theme.unfocused_border_style()
         }
       }, rect}
    ]
  end

  defp render_task_detail(%State{selected_task: task}, rect) do
    lines =
      task
      |> DalaDev.Tui.State.task_detail()
      |> Enum.map(&to_line/1)

    [
      {%Paragraph{
         text: lines,
         block: %Block{
           borders: [:all],
           border_type: :rounded,
           border_style: Theme.unfocused_border_style()
         }
       }, rect}
    ]
  end

  # ── Debug Detail ────────────────────────────────────────────

  defp render_debug_detail(%State{selected_remote: nil}, rect) do
    [
      {%Paragraph{
         text: "No remote node selected\n\nSelect a node from the Debug tab to inspect.",
         block: %Block{
           borders: [:all],
           border_type: :rounded,
           border_style: Theme.unfocused_border_style()
         }
       }, rect}
    ]
  end

  defp render_debug_detail(%State{selected_remote: remote, loading: loading}, rect) do
    lines =
      if loading do
        [
          %Line{spans: [%Span{content: " ", style: %Style{}}]},
          %Line{
            spans: [%Span{content: "Loading remote node info...", style: Theme.gold_style()}]
          },
          %Line{spans: [%Span{content: "", style: %Style{}}]},
          %Line{
            spans: [%Span{content: "Querying #{remote.node}...", style: Theme.dim_text_style()}]
          }
        ]
      else
        remote
        |> DalaDev.Tui.State.remote_detail()
        |> Enum.map(&to_line/1)
      end

    [
      {%Paragraph{
         text: lines,
         block: %Block{
           borders: [:all],
           border_type: :rounded,
           border_style: Theme.unfocused_border_style()
         }
       }, rect}
    ]
  end

  # ── Output ──────────────────────────────────────────────────

  defp render_output(%State{last_run_output: nil}, rect) do
    [
      {%Paragraph{
         text: "No output yet.\n\nRun a task to see results here.",
         block: %Block{
           borders: [:all],
           border_type: :rounded,
           border_style: Theme.unfocused_border_style()
         }
       }, rect}
    ]
  end

  defp render_output(%State{last_run_output: output}, rect) do
    [
      {%Paragraph{
         text: output,
         block: %Block{
           borders: [:all],
           border_type: :rounded,
           border_style: Theme.unfocused_border_style()
         }
       }, rect}
    ]
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp to_line(text) when is_binary(text) do
    %Line{spans: [%Span{content: " " <> text, style: %Style{fg: :white}}]}
  end

  defp to_line(%Line{} = line), do: line

  defp to_line(other),
    do: %Line{spans: [%Span{content: inspect(other), style: %Style{fg: :white}}]}
end
