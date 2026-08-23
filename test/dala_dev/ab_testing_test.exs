defmodule DalaDev.ABTestingTest do
  use ExUnit.Case, async: false

  alias DalaDev.ABTesting

  @experiment %{
    name: "test experiment",
    variants: ["strategy_a", "strategy_b"],
    metric: :reductions,
    duration_per_variant: 10
  }

  describe "run/2" do
    test "runs a small experiment on the local node" do
      {:ok, results} =
        ABTesting.run(@experiment, nodes: [Node.self()], iterations: 2, warmup: 1)

      assert length(results) == 2
      assert Enum.all?(results, &(&1.values != []))
      assert Enum.all?(results, &is_atom(&1.node))
      variants = Enum.map(results, & &1.variant)
      assert variants == ["strategy_a", "strategy_b"]
    end

    test "returns error on invalid experiment" do
      assert {:error, _} = ABTesting.run(%{variants: nil, metric: :reductions}, nodes: [])
    end
  end

  describe "analyze/1" do
    test "computes per-variant stats and picks a winner" do
      results = [
        %{
          variant: "a",
          node: :a@x,
          metric: :response_time,
          values: [10, 12, 11],
          stats: %{mean: 11.0, std_dev: 1.0}
        },
        %{
          variant: "b",
          node: :a@x,
          metric: :response_time,
          values: [20, 22, 21],
          stats: %{mean: 21.0, std_dev: 1.0}
        }
      ]

      assert {:ok, analysis} = ABTesting.analyze(results)
      assert analysis.summary.variant_count == 2
      assert length(analysis.variant_stats) == 2

      stat_a = Enum.find(analysis.variant_stats, &(&1.variant == "a"))
      assert stat_a.mean == 11.0
      assert stat_a.count == 3
      assert stat_a.min == 10
      assert stat_a.max == 12

      assert analysis.winner == "a"
      assert analysis.confidence == 0.95
    end

    test "handles empty results" do
      assert {:ok, analysis} = ABTesting.analyze([])
      assert analysis.winner == nil
    end
  end

  describe "generate_report/2" do
    @results [
      %{
        variant: "a",
        node: :a@x,
        metric: :response_time,
        values: [10],
        stats: %{mean: 10.0, std_dev: 0.5}
      }
    ]

    test "generates HTML report by default" do
      assert {:ok, html} = ABTesting.generate_report(@results)
      assert html =~ "<!DOCTYPE html>"
      assert html =~ "A/B Test Report"
      assert html =~ "Variant Statistics"
    end

    test "generates text report" do
      assert {:ok, text} = ABTesting.generate_report(@results, format: :text)
      assert text =~ "Variant: a"
      assert text =~ "Mean: 10.0"
    end

    test "writes to file when :output given" do
      path = Path.join(["test_tmp", "ab_#{System.unique_integer()}", "ab_report.html"])
      File.mkdir_p!(Path.dirname(path))
      on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

      assert :ok = ABTesting.generate_report(@results, output: path)
      assert File.exists?(path)
    end

    test "returns error for unwritable output" do
      assert {:error, _} = ABTesting.generate_report(@results, output: "/nonexistent/x.html")
    end
  end
end
