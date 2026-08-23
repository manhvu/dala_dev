defmodule DalaDev.Tui.Views.HelpOverlayTest do
  use ExUnit.Case, async: true

  alias DalaDev.Tui.Views.HelpOverlay
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Block, Paragraph}

  test "render/1 returns a list of {widget, rect} tuples" do
    rect = %Rect{x: 0, y: 0, width: 80, height: 24}

    assert [{%Paragraph{block: %Block{border_type: :double}} = widget, ^rect}] =
             HelpOverlay.render(rect)

    # the bordered block carries the overlay's title
    assert inspect(widget.block.title) =~ "Keyboard Reference"
  end

  test "overlay contains navigation hints and key rows" do
    rect = %Rect{x: 0, y: 0, width: 80, height: 40}
    [{widget, _}] = HelpOverlay.render(rect)

    text = inspect(widget.text)
    assert text =~ "Navigation"
    assert text =~ "Move selection down"
  end
end
