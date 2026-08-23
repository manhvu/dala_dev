defmodule DalaDev.Server.LogBufferTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(DalaDev.Server.LogBuffer)
    :ok
  end

  test "starts empty" do
    assert [] = DalaDev.Server.LogBuffer.get()
  end

  test "pushes lines and returns them newest-first" do
    DalaDev.Server.LogBuffer.push(%{line: "first"})
    DalaDev.Server.LogBuffer.push(%{line: "second"})
    # casts are async — wait for the buffer to process both
    wait_until(fn -> length(DalaDev.Server.LogBuffer.get()) == 2 end)

    [%{line: "second"}, %{line: "first"}] = DalaDev.Server.LogBuffer.get()
  end

  test "clears all lines" do
    DalaDev.Server.LogBuffer.push(%{line: "x"})
    wait_until(fn -> DalaDev.Server.LogBuffer.get() != [] end)

    DalaDev.Server.LogBuffer.clear()
    wait_until(fn -> DalaDev.Server.LogBuffer.get() == [] end)
    assert [] = DalaDev.Server.LogBuffer.get()
  end

  defp wait_until(fun, tries \\ 50)

  defp wait_until(_fun, 0), do: flunk("condition not met")

  defp wait_until(fun, tries) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      wait_until(fun, tries - 1)
    end
  end
end

defmodule DalaDev.Server.ElixirLogBufferTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(DalaDev.Server.ElixirLogBuffer)
    :ok
  end

  test "starts empty" do
    assert [] = DalaDev.Server.ElixirLogBuffer.get()
  end

  test "pushes lines newest-first and clears" do
    DalaDev.Server.ElixirLogBuffer.push(%{message: "a"})
    DalaDev.Server.ElixirLogBuffer.push(%{message: "b"})
    wait_until(fn -> length(DalaDev.Server.ElixirLogBuffer.get()) == 2 end)

    [%{message: "b"}, %{message: "a"}] = DalaDev.Server.ElixirLogBuffer.get()

    DalaDev.Server.ElixirLogBuffer.clear()
    wait_until(fn -> DalaDev.Server.ElixirLogBuffer.get() == [] end)
  end

  defp wait_until(fun, tries \\ 50)

  defp wait_until(_fun, 0), do: flunk("condition not met")

  defp wait_until(fun, tries) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      wait_until(fun, tries - 1)
    end
  end
end
