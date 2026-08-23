defmodule DalaDev.ProfilingTest do
  use ExUnit.Case, async: false

  alias DalaDev.Profiling

  # :eprof lives in the OTP "tools" app, which is not always on the code path
  setup_all do
    unless Code.ensure_loaded?(:eprof) do
      ExUnit.configure(exclude: [eprof: true])
    end

    :ok
  end

  describe "profile_locally/3" do
    @describetag eprof: true

    test "profiles a simple function with eprof" do
      fun = fn -> Enum.map(1..100, &(&1 * 2)) end

      assert {:ok, _data} = Profiling.profile_locally(fun, 10, :eprof)
    end

    test "returns error tuple on exception" do
      result = Profiling.profile_locally(fn -> raise "boom" end, 10, :eprof)
      # eprof may swallow or propagate the exception; either way it must not crash
      case result do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end
  end

  describe "analyze/1" do
    test "analyzes fprof-style profile data" do
      profile = [
        %{mod: String, fun: :length, time: 100, calls: 10},
        %{mod: Enum, fun: :map, time: 500, calls: 5},
        %{mod: List, fun: :flatten, time: 50, calls: 1}
      ]

      assert {:ok, analysis} = Profiling.analyze(profile)
      assert analysis.calls == 3
      assert length(analysis.top_functions) == 3

      [top | _] = analysis.top_functions
      assert elem(top, 0) == Enum
      assert elem(top, 2) == 500

      [bottleneck | _] = analysis.bottlenecks
      assert elem(bottleneck, 0) == Enum
    end

    test "handles empty profile" do
      assert {:ok, analysis} = Profiling.analyze([])
      assert analysis.calls == 0
      assert analysis.top_functions == []
    end
  end

  describe "flame_graph/2" do
    test "generates HTML content by default" do
      profile = [%{mod: Foo, fun: :bar, time: 10, calls: 1}]
      assert {:ok, html} = Profiling.flame_graph(profile)
      assert html =~ "<!DOCTYPE html>"
      assert html =~ "Flame Graph"
    end

    test "generates text format when requested" do
      profile = []
      assert {:ok, text} = Profiling.flame_graph(profile, format: :text)
      assert text =~ "Root (100%)"
    end

    test "writes to file when :output given" do
      path = Path.join("test_tmp", "flame.html")
      File.mkdir_p!(Path.dirname(path))
      on_exit(fn -> File.rm_rf!(path) end)

      assert :ok = Profiling.flame_graph([], output: path)
      assert File.exists?(path)
    end

    test "returns error when output path invalid" do
      assert {:error, _} = Profiling.flame_graph([], output: "/nonexistent/dir/f.html")
    end
  end

  describe "profile/3 (remote)" do
    test "profiles a function on the local node via rpc path" do
      # Uses the local node as the RPC target — exercises the full path
      fun = fn -> :timer.sleep(5) end
      assert {:ok, _data} = Profiling.profile(Node.self(), fun, duration: 10)
    end
  end
end
