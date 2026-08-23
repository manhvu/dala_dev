defmodule DalaDev.TuiTest do
  use ExUnit.Case, async: false

  alias DalaDev.Tui

  describe "explore/1" do
    test "runs the TUI with a test starter and returns when it exits" do
      # Inject a starter that immediately exits — verifies the monitor loop
      Application.put_env(:dala_dev, :tui_starter, fn _opts ->
        {:ok, spawn(fn -> :ok end)}
      end)

      on_exit(fn -> Application.delete_env(:dala_dev, :tui_starter) end)

      assert :ok = Tui.explore(test_mode: {80, 24})
    end

    test "accepts a custom named process starter" do
      test_pid = self()

      Application.put_env(:dala_dev, :tui_starter, fn opts ->
        send(test_pid, {:starter_opts, opts})
        {:ok, spawn(fn -> :ok end)}
      end)

      on_exit(fn -> Application.delete_env(:dala_dev, :tui_starter) end)

      assert :ok = Tui.explore(name: :tui_test_name)
      assert_received {:starter_opts, [name: :tui_test_name]}
    end
  end
end
