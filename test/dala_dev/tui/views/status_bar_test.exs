defmodule DalaDev.Tui.Views.StatusBarTest do
  use ExUnit.Case, async: true

  alias DalaDev.Tui.State
  alias DalaDev.Tui.Views.StatusBar
  alias ExRatatui.Layout.Rect

  @rect %Rect{x: 0, y: 0, width: 80, height: 3}

  defp render_text(state) do
    [{widget, @rect}] = StatusBar.render(state, @rect)
    inspect(widget.text)
  end

  test "renders Ready by default" do
    state = State.new([], [], [])

    assert render_text(state) =~ "Ready"
  end

  test "shows status message when set" do
    state = State.new([], [], [])
    state = %{state | status_message: "Deploying to Pixel 8..."}

    text = render_text(state)
    assert text =~ "Deploying to Pixel 8..."
    refute text =~ "Ready"
  end

  test "status message takes precedence over version info" do
    state = State.new([], [], [])

    state = %{
      state
      | status_message: "Refreshing...",
        version_info: %{dala_version: "0.8.0", otp_version: "27"}
    }

    text = render_text(state)
    assert text =~ "Refreshing..."
    refute text =~ "dala:"
  end

  test "shows version info when no status message is present" do
    state = State.new([], [], [])

    state = %{
      state
      | version_info: %{
          dala_version: "0.8.0",
          otp_version: "27.1",
          device_count: 2,
          node_count: 1
        }
    }

    text = render_text(state)

    assert text =~ "dala: 0.8.0"
    assert text =~ "OTP: 27.1"
    assert text =~ "devices: 2"
    assert text =~ "nodes: 1"
  end

  test "version info falls back to N/A and 0 for missing fields" do
    state = State.new([], [], [])
    state = %{state | version_info: %{}}

    text = render_text(state)

    assert text =~ "N/A"
    assert text =~ "devices: 0"
    assert text =~ "nodes: 0"
  end
end
