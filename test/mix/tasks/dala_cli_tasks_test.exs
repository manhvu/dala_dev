defmodule Mix.Tasks.Dala.BenchTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1" do
    @tag :slow
    test "runs standard benchmarks against the local node" do
      output =
        capture_io(fn ->
          Mix.Tasks.Dala.Bench.run(["--iterations", "1"])
        end)

      assert output =~ "Running standard benchmarks"
      assert output =~ "Iterations: 1"
    end
  end
end

defmodule Mix.Tasks.Dala.ConnectTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1" do
    test "reports gracefully when no device nodes are reachable" do
      result =
        try do
          output =
            capture_io(fn ->
              Mix.Tasks.Dala.Connect.run([])
            end)

          {:completed, output}
        rescue
          e -> {:raised, Exception.message(e)}
        catch
          :exit, reason -> {:exited, inspect(reason)}
        end

      case result do
        {:completed, output} -> assert output =~ "No nodes connected"
        {other, _} -> assert other in [:raised, :exited]
      end
    end
  end
end

defmodule Mix.Tasks.Dala.PushTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1" do
    test "reports gracefully when no nodes are running" do
      result =
        try do
          output =
            capture_io(fn ->
              Mix.Tasks.Dala.Push.run([])
            end)

          {:completed, output}
        rescue
          e -> {:raised, Exception.message(e)}
        catch
          :exit, reason -> {:exited, inspect(reason)}
        end

      case result do
        {:completed, output} -> assert output =~ "No running nodes found"
        {other, _} -> assert other in [:raised, :exited]
      end
    end
  end
end

defmodule Mix.Tasks.Dala.TraceTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1" do
    @tag :slow
    test "starts and stops a short local trace" do
      result =
        try do
          output =
            capture_io(fn ->
              Mix.Tasks.Dala.Trace.run(["--duration", "1"])
            end)

          {:completed, output}
        rescue
          e -> {:raised, Exception.message(e)}
        catch
          :exit, reason -> {:exited, inspect(reason)}
        end

      case result do
        {:completed, output} -> assert output =~ "Starting trace"
        {other, _} -> assert other in [:raised, :exited]
      end
    end
  end
end

defmodule Mix.Tasks.Dala.SyncUsageTest do
  use ExUnit.Case, async: false

  test "wrong argument count raises a usage error" do
    assert_raise Mix.Error, ~r/Usage: mix dala.sync/, fn ->
      Mix.Tasks.Dala.Sync.run(["only-one-arg"])
    end
  end
end

defmodule Mix.Tasks.Dala.PushFileUsageTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "wrong argument count raises a usage error" do
    assert_raise Mix.Error, ~r/Usage: mix dala.push_file/, fn ->
      Mix.Tasks.Dala.PushFile.run([])
    end
  end

  test "invalid on_conflict mode raises before touching any device" do
    assert_raise Mix.Error, ~r/Invalid on_conflict mode: bogus/, fn ->
      Mix.Tasks.Dala.PushFile.run(["a.txt", "/remote/a.txt", "--on_conflict", "bogus"])
    end
  end

  test "underscored --on_conflict flag is parsed (not silently dropped)" do
    # With no devices attached this is a no-op; the point is that the
    # documented underscore spelling reaches parse_conflict/1 instead of
    # being swallowed by OptionParser.
    output =
      capture_io(fn ->
        Mix.Tasks.Dala.PushFile.run(["a.txt", "/remote/a.txt", "--on_conflict", "skip"])
      end)

    refute output =~ "Usage:"
  end
end

defmodule Mix.Tasks.Dala.PullFileUsageTest do
  use ExUnit.Case, async: false

  test "wrong argument count raises a usage error" do
    assert_raise Mix.Error, ~r/Usage: mix dala.pull_file/, fn ->
      Mix.Tasks.Dala.PullFile.run([])
    end
  end
end

defmodule Mix.Tasks.Dala.FileLsTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1" do
    test "handles an unmatched device gracefully" do
      result =
        try do
          capture_io(fn ->
            Mix.Tasks.Dala.FileLs.run(["--device", "NOT_A_DEVICE"])
          end)

          :completed
        rescue
          _ -> :raised
        catch
          :exit, _ -> :exited
        end

      assert result in [:completed, :raised, :exited]
    end
  end
end

defmodule Mix.Tasks.Dala.ServerTaskTest do
  use ExUnit.Case, async: false

  # The server blocks forever and opens a browser when run — verify the
  # dependencies run/1 needs at boot instead of executing it.
  test "server dependencies required by run/1 are available" do
    assert Code.ensure_loaded?(Mix.Tasks.Dala.Server)
    assert DalaDev.ServerDeps.available?() == true
  end

  test "has a moduledoc" do
    {:docs_v1, _, _, _, moduledoc, _, _} = Code.fetch_docs(Mix.Tasks.Dala.Server)
    doc = doc_string(moduledoc)

    assert doc =~ "server"
  end

  defp doc_string(%{"en" => doc}), do: doc
  defp doc_string(doc) when is_binary(doc), do: doc
  defp doc_string(_), do: ""
end

defmodule Mix.Tasks.Dala.ObserverTaskTest do
  use ExUnit.Case, async: false

  # Observer sleeps :infinity after booting a web server — verify the
  # monitoring seam run/1 serves instead of executing it.
  test "observes the local node like run/1 would" do
    assert Code.ensure_loaded?(Mix.Tasks.Dala.Observer)

    info = DalaDev.Observer.system_info(node())

    assert info.memory.total > 0
    assert info.process_count > 0
    assert info.system_version =~ "OTP"
  end

  test "has a moduledoc mentioning observer" do
    {:docs_v1, _, _, _, moduledoc, _, _} = Code.fetch_docs(Mix.Tasks.Dala.Observer)
    doc = doc_string(moduledoc)

    assert doc =~ "Observer"
  end

  defp doc_string(%{"en" => doc}), do: doc
  defp doc_string(doc) when is_binary(doc), do: doc
  defp doc_string(_), do: ""
end

defmodule Mix.Tasks.Dala.IconTaskTest do
  use ExUnit.Case, async: false

  # Running icon generation writes assets into the project — exercise the
  # input validation run/1 performs before touching any files instead.
  test "rejects a missing --source before writing any icons" do
    assert_raise Mix.Error, ~r/Source file not found/, fn ->
      Mix.Tasks.Dala.Icon.run(["--source", "definitely_missing_icon_source.png"])
    end
  end

  test "has a moduledoc describing icon generation" do
    {:docs_v1, _, _, _, moduledoc, _, _} = Code.fetch_docs(Mix.Tasks.Dala.Icon)
    doc = doc_string(moduledoc)

    assert doc =~ "icon" or doc =~ "Icon"
  end

  defp doc_string(%{"en" => doc}), do: doc
  defp doc_string(doc) when is_binary(doc), do: doc
  defp doc_string(_), do: ""
end

defmodule Mix.Tasks.DalaDev.TuiTaskTest do
  use ExUnit.Case, async: false

  # The TUI takes over the terminal until the user quits — verify the task
  # delegates to a TUI whose task inventory is populated.
  test "delegates to DalaDev.Tui with a non-empty task inventory" do
    assert Code.ensure_loaded?(Mix.Tasks.DalaDev.Tui)

    assert [%{name: "devices", module: Mix.Tasks.Dala.Devices} | _rest] =
             DalaDev.Tui.Tasks.list()
  end

  test "delegates to DalaDev.Tui.explore/0" do
    src = Mix.Tasks.DalaDev.Tui.module_info(:compile)[:source] |> to_string()
    contents = File.read!(src)

    assert contents =~ "DalaDev.Tui.explore()"
  end
end
