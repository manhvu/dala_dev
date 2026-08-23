defmodule DalaDev.QRTest do
  use ExUnit.Case, async: true

  alias DalaDev.QR

  describe "render/1" do
    test "renders a non-empty string of block characters" do
      qr = QR.render("https://dala.dev")
      assert byte_size(qr) > 0
      # Unicode half-block characters used for terminal rendering
      assert qr =~ ~r/[▀▄█ ]/
    end

    test "renders multiple lines" do
      qr = QR.render("hello")
      lines = String.split(qr, "\n")
      assert length(lines) > 1
    end

    test "all lines have equal width (quiet zone padding)" do
      qr = QR.render("test-content-123")

      widths =
        qr |> String.split("\n") |> Enum.map(&String.length/1) |> Enum.uniq()

      assert length(widths) == 1
    end
  end

  describe "print/1" do
    test "prints the rendered QR code" do
      output = ExUnit.CaptureIO.capture_io(fn -> QR.print("hi") end)
      assert output =~ ~r/[▀▄█]/
    end
  end
end
