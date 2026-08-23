defmodule DalaDev.Server.ElixirLoggerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  require Logger

  alias DalaDev.Server.ElixirLogBuffer
  alias DalaDev.Server.ElixirLogger

  @topic "elixir_logs"

  # Runs without any buffer/PubSub running — must not raise.
  test "log/2 is silent and safe when buffers are not running" do
    event = %{
      level: :info,
      msg: {:string, "orphan"},
      meta: %{domain: [:elixir], time: nil}
    }

    assert ElixirLogger.log(event, %{}) == :ok
  end

  describe "log/2 with buffer running" do
    setup do
      start_supervised!({Phoenix.PubSub, name: DalaDev.PubSub})
      start_supervised!(ElixirLogBuffer)
      Phoenix.PubSub.subscribe(DalaDev.PubSub, @topic)
      :ok
    end

    # OTP logger metadata is a map, not a keyword list
    defp elixir_event(level, msg, extra_meta \\ %{}) do
      %{
        level: level,
        msg: msg,
        meta:
          Map.merge(
            %{domain: [:elixir], time: System.system_time(:microsecond), module: __MODULE__},
            extra_meta
          )
      }
    end

    defp wait_for_buffer(fun, tries \\ 50)

    defp wait_for_buffer(_fun, 0), do: flunk("buffer never received the line")

    defp wait_for_buffer(fun, tries) do
      if fun.() do
        :ok
      else
        Process.sleep(10)
        wait_for_buffer(fun, tries - 1)
      end
    end

    test "captures an Elixir-domain string message into the buffer" do
      assert ElixirLogger.log(elixir_event(:info, {:string, ["hello ", "world"]}), %{}) == :ok

      wait_for_buffer(fn -> ElixirLogBuffer.get() != [] end)
      [line] = ElixirLogBuffer.get()

      assert line.level == "I"
      assert line.message == "hello world"
      assert line.module == __MODULE__
      assert line.ts =~ ":"
      assert is_integer(line.id)
    end

    test "ignores events outside the Elixir domain" do
      event = %{level: :info, msg: {:string, "otp noise"}, meta: %{domain: [:otp]}}

      assert ElixirLogger.log(event, %{}) == :ok
      Process.sleep(20)
      assert ElixirLogBuffer.get() == []
    end

    test "maps levels to display characters" do
      for {level, _char} <- [error: "E", warning: "W", info: "I", debug: "D"] do
        assert ElixirLogger.log(elixir_event(level, {:string, "#{level}"}, %{time: nil}), %{}) ==
                 :ok
      end

      wait_for_buffer(fn -> length(ElixirLogBuffer.get()) == 4 end)

      chars = Enum.map(ElixirLogBuffer.get(), & &1.level) |> Enum.sort()
      assert chars == ["D", "E", "I", "W"]
    end

    test "formats report messages with inspect" do
      assert ElixirLogger.log(elixir_event(:info, {:report, %{key: "value"}}, %{time: nil}), %{}) ==
               :ok

      wait_for_buffer(fn -> ElixirLogBuffer.get() != [] end)
      [%{message: msg}] = ElixirLogBuffer.get()

      assert msg =~ "key"
      assert msg =~ "value"
    end

    test "survives malformed :format messages" do
      bad = {:format, "~w bad", []}

      assert ElixirLogger.log(elixir_event(:error, bad, %{time: nil}), %{}) == :ok

      wait_for_buffer(fn -> ElixirLogBuffer.get() != [] end)
      [%{level: "E", message: msg}] = ElixirLogBuffer.get()

      assert msg =~ "bad"
    end

    test "missing timestamp yields an empty ts" do
      assert ElixirLogger.log(elixir_event(:info, {:string, "no time"}, %{time: nil}), %{}) == :ok

      wait_for_buffer(fn -> ElixirLogBuffer.get() != [] end)
      [%{ts: ts}] = ElixirLogBuffer.get()

      assert ts == ""
    end

    test "broadcasts each captured line on the elixir_logs topic" do
      assert ElixirLogger.log(elixir_event(:info, {:string, "broadcast me"}, %{time: nil}), %{}) ==
               :ok

      assert_receive {:elixir_log_line, line}, 1_000
      assert line.message == "broadcast me"
    end

    test "attach/detach round-trip captures real Logger output" do
      assert :ok = ElixirLogger.attach()

      capture_log(fn ->
        Logger.info("dala logger integration probe")
      end)

      wait_for_buffer(fn ->
        Enum.any?(ElixirLogBuffer.get(), &(&1.message =~ "integration probe"))
      end)

      assert :ok = ElixirLogger.detach()

      capture_log(fn ->
        Logger.info("should not be captured")
      end)

      Process.sleep(20)

      refute Enum.any?(ElixirLogBuffer.get(), &(&1.message =~ "should not be captured"))
    end
  end

  describe "handler lifecycle callbacks" do
    test "adding_handler/1 and removing_handler/1 accept config" do
      assert {:ok, %{}} = ElixirLogger.adding_handler(%{})
      assert :ok = ElixirLogger.removing_handler(%{})
    end
  end
end
