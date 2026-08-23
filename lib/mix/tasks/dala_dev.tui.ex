defmodule Mix.Tasks.DalaDev.Tui do
  @moduledoc """
  Launches the dala_dev Terminal UI dashboard.

  ## Usage

      mix dala_dev.tui

  This starts an interactive four-tab TUI where you can:
  - Browse discovered devices (Android/iOS) with node and connection info
  - Run `mix dala.*` tasks from the terminal
  - View deployment status and logs
  - Inspect remote nodes (version, screen info, memory, latency)
  - Access diagnostics and doctor output

  Press `?` inside the TUI for keyboard shortcuts, `q` to quit.

  ## Examples

      # Launch the TUI
      mix dala_dev.tui
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    # Ensure the application is started
    {:ok, _apps} = Application.ensure_all_started(:dala_dev)

    # Start the TUI (blocks until user quits)
    DalaDev.Tui.explore()
  end
end
