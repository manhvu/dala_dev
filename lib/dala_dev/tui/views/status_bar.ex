defmodule DalaDev.Tui.Views.StatusBar do
  @moduledoc """
  Status bar view: shows connection info, version, and status messages.

  Pure function — takes state and rect, returns `[{widget, rect}]`.
  """

  alias DalaDev.Tui.State
  alias DalaDev.Tui.Theme
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.{Block, Paragraph}

  @doc """
  Renders the status bar with version info and status messages.
  """
  @spec render(State.t(), Rect.t()) :: [{struct(), Rect.t()}]
  def render(state, rect) do
    [
      {%Paragraph{
         text: status_line(state),
         block: %Block{
           borders: [:all],
           border_type: :rounded,
           border_style: Theme.unfocused_border_style()
         }
       }, rect}
    ]
  end

  defp status_line(%State{status_message: msg}) when is_binary(msg) do
    %Line{
      spans: [
        %Span{content: " ", style: %Style{}},
        %Span{content: msg, style: Theme.gold_style()},
        %Span{content: " ", style: %Style{}}
      ]
    }
  end

  defp status_line(%State{version_info: info}) when is_map(info) do
    %Line{
      spans: [
        %Span{content: " ", style: %Style{}},
        %Span{content: "dala: #{info[:dala_version] || "N/A"}", style: Theme.dim_text_style()},
        %Span{content: " | ", style: Theme.dim_text_style()},
        %Span{content: "OTP: #{info[:otp_version] || "N/A"}", style: Theme.dim_text_style()},
        %Span{content: " | ", style: Theme.dim_text_style()},
        %Span{content: "devices: #{info[:device_count] || 0}", style: Theme.dim_text_style()},
        %Span{content: " | ", style: Theme.dim_text_style()},
        %Span{content: "nodes: #{info[:node_count] || 0}", style: Theme.dim_text_style()},
        %Span{content: " ", style: %Style{}}
      ]
    }
  end

  defp status_line(_state) do
    %Line{
      spans: [
        %Span{content: " ", style: %Style{}},
        %Span{content: "Ready", style: Theme.green_style()},
        %Span{content: " ", style: %Style{}}
      ]
    }
  end
end
