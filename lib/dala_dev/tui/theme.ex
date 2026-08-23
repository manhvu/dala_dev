defmodule DalaDev.Tui.Theme do
  @moduledoc """
  Color, style, and rich-text constants for the dala_dev TUI.

  Provides a consistent visual palette. All functions are pure.
  """

  # ── Colors ──────────────────────────────────────────────────

  @dala_orange {:rgb, 255, 107, 53}
  @cornflower {:rgb, 100, 149, 237}
  @gold {:rgb, 255, 215, 0}
  @highlight_bg {:rgb, 40, 40, 60}
  @dim_border {:rgb, 60, 60, 80}
  @dim_text {:rgb, 150, 150, 170}

  @green :green
  @red :red

  @doc "Dala brand orange."
  @spec dala_orange() :: ExRatatui.Style.color()
  def dala_orange, do: @dala_orange

  @doc "Cornflower blue for focused borders."
  @spec cornflower() :: ExRatatui.Style.color()
  def cornflower, do: @cornflower

  @doc "Gold for highlights."
  @spec gold() :: ExRatatui.Style.color()
  def gold, do: @gold

  @doc "Green for success/connected status."
  @spec green() :: ExRatatui.Style.color()
  def green, do: @green

  @doc "Red for errors/disconnected status."
  @spec red() :: ExRatatui.Style.color()
  def red, do: @red

  @doc "Highlight style for selected items."
  @spec highlight_style() :: ExRatatui.Style.t()
  def highlight_style do
    %ExRatatui.Style{
      fg: @gold,
      bg: @highlight_bg,
      modifiers: [:bold]
    }
  end

  @doc "Focused panel border style."
  @spec focused_border_style() :: ExRatatui.Style.t()
  def focused_border_style do
    %ExRatatui.Style{fg: @cornflower}
  end

  @doc "Unfocused panel border style."
  @spec unfocused_border_style() :: ExRatatui.Style.t()
  def unfocused_border_style do
    %ExRatatui.Style{fg: @dim_border}
  end

  @doc "Border style based on focus state."
  @spec border_style(boolean()) :: ExRatatui.Style.t()
  def border_style(focused?) do
    if focused?, do: focused_border_style(), else: unfocused_border_style()
  end

  @doc "Dim text style."
  @spec dim_text_style() :: ExRatatui.Style.t()
  def dim_text_style do
    %ExRatatui.Style{fg: @dim_text}
  end

  @doc "Green text style."
  @spec green_style() :: ExRatatui.Style.t()
  def green_style do
    %ExRatatui.Style{fg: @green}
  end

  @doc "Red text style."
  @spec red_style() :: ExRatatui.Style.t()
  def red_style do
    %ExRatatui.Style{fg: @red}
  end

  @doc "Gold text style."
  @spec gold_style() :: ExRatatui.Style.t()
  def gold_style do
    %ExRatatui.Style{fg: @gold, modifiers: [:bold]}
  end

  @doc "Branded header title."
  @spec brand_title(String.t()) :: ExRatatui.Text.Line.t()
  def brand_title(breadcrumb) do
    _base = " ⚡ DalaDev TUI "

    crumb =
      if breadcrumb != "" do
        "│ #{breadcrumb}"
      else
        ""
      end

    %ExRatatui.Text.Line{
      spans: [
        %ExRatatui.Text.Span{content: " ⚡ ", style: %ExRatatui.Style{}},
        %ExRatatui.Text.Span{
          content: "DalaDev",
          style: %ExRatatui.Style{fg: @dala_orange, modifiers: [:bold]}
        },
        %ExRatatui.Text.Span{
          content: " TUI",
          style: %ExRatatui.Style{fg: @gold, modifiers: [:bold]}
        },
        %ExRatatui.Text.Span{content: crumb, style: %ExRatatui.Style{fg: @cornflower}}
      ]
    }
  end

  @doc "Section title."
  @spec section_title(String.t()) :: ExRatatui.Text.Line.t()
  def section_title(content) do
    %ExRatatui.Text.Line{
      spans: [
        %ExRatatui.Text.Span{content: " ", style: %ExRatatui.Style{}},
        %ExRatatui.Text.Span{
          content: content,
          style: %ExRatatui.Style{fg: @cornflower, modifiers: [:bold]}
        }
      ]
    }
  end

  @doc "Key pill for footer/help."
  @spec key_pill(String.t()) :: ExRatatui.Text.Span.t()
  def key_pill(label) do
    %ExRatatui.Text.Span{
      content: " #{label} ",
      style: %ExRatatui.Style{bg: :cyan, fg: :black, modifiers: [:bold]}
    }
  end

  @doc "Dim span for descriptions."
  @spec dim_span(String.t()) :: ExRatatui.Text.Span.t()
  def dim_span(text) do
    %ExRatatui.Text.Span{content: text, style: %ExRatatui.Style{fg: @dim_text}}
  end

  @doc "Footer line with key hints."
  @spec footer_line([{String.t(), String.t()}]) :: ExRatatui.Text.Line.t()
  def footer_line(entries) do
    spans =
      Enum.flat_map(entries, fn {label, description} ->
        [key_pill(label), dim_span(" #{description} ")]
      end)

    %ExRatatui.Text.Line{spans: spans}
  end
end
