defmodule DalaDev.Tui.ThemeTest do
  use ExUnit.Case, async: true

  alias DalaDev.Tui.Theme

  describe "color constants" do
    test "dala_orange is the brand orange" do
      assert Theme.dala_orange() == {:rgb, 255, 107, 53}
    end

    test "cornflower is cornflower blue" do
      assert Theme.cornflower() == {:rgb, 100, 149, 237}
    end

    test "gold is gold" do
      assert Theme.gold() == {:rgb, 255, 215, 0}
    end

    test "green and red are ANSI colors" do
      assert Theme.green() == :green
      assert Theme.red() == :red
    end
  end

  describe "styles" do
    test "highlight_style uses gold on highlight background with bold" do
      style = Theme.highlight_style()
      assert style.fg == Theme.gold()
      assert style.modifiers == [:bold]
      assert style.bg == {:rgb, 40, 40, 60}
    end

    test "focused_border_style uses cornflower" do
      assert Theme.focused_border_style().fg == Theme.cornflower()
    end

    test "unfocused_border_style uses dim border" do
      style = Theme.unfocused_border_style()
      assert style.fg == {:rgb, 60, 60, 80}
    end

    test "border_style/1 dispatches on focus state" do
      assert Theme.border_style(true) == Theme.focused_border_style()
      assert Theme.border_style(false) == Theme.unfocused_border_style()
    end

    test "dim_text_style has dim foreground" do
      assert %ExRatatui.Style{} = Theme.dim_text_style()
    end

    test "green_style and red_style use ANSI colors" do
      assert Theme.green_style().fg == :green
      assert Theme.red_style().fg == :red
    end

    test "gold_style is bold gold" do
      style = Theme.gold_style()
      assert style.fg == Theme.gold()
      assert style.modifiers == [:bold]
    end
  end

  describe "brand_title/1" do
    test "includes DalaDev TUI branding spans" do
      line = Theme.brand_title("")
      contents = Enum.map(line.spans, & &1.content)
      combined = Enum.join(contents)

      assert combined =~ "DalaDev"
      assert combined =~ "TUI"
    end

    test "appends breadcrumb when non-empty" do
      line = Theme.brand_title("Devices")
      contents = Enum.map(line.spans, & &1.content)
      combined = Enum.join(contents)

      assert combined =~ "│ Devices"
    end

    test "omits breadcrumb separator when empty" do
      line = Theme.brand_title("")
      refute Enum.any?(line.spans, &(&1.content =~ "│"))
    end
  end

  describe "section_title/1" do
    test "wraps content in a styled line" do
      line = Theme.section_title("Details")
      assert [%{content: " ", style: _}, %{content: "Details", style: style}] = line.spans
      assert style.modifiers == [:bold]
    end
  end

  describe "key_pill/1" do
    test "pads label with spaces and styles it" do
      span = Theme.key_pill("q")
      assert span.content == " q "
      assert span.style.bg == :cyan
      assert span.style.fg == :black
    end
  end

  describe "dim_span/1" do
    test "returns a span with the given text" do
      span = Theme.dim_span("some hint")
      assert span.content == "some hint"
    end
  end

  describe "footer_line/1" do
    test "interleaves key pills and descriptions" do
      line = Theme.footer_line([{"q", "quit"}, {"?", "help"}])
      contents = Enum.map(line.spans, & &1.content)

      assert contents == [" q ", " quit ", " ? ", " help "]
    end

    test "returns an empty line for no entries" do
      line = Theme.footer_line([])
      assert line.spans == []
    end
  end
end
