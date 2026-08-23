defmodule DalaDev.CITestingTest do
  use ExUnit.Case, async: false

  alias DalaDev.CITesting

  defp suite(opts \\ []) do
    %{
      name: "test suite",
      tests: [
        %{name: "passes", module: __MODULE__, test_fun: fn -> :ok end, timeout: 5_000, tags: []},
        %{
          name: "fails",
          module: __MODULE__,
          test_fun: fn -> {:error, :boom} end,
          timeout: 5_000,
          tags: []
        }
      ],
      setup: Keyword.get(opts, :setup),
      teardown: Keyword.get(opts, :teardown)
    }
  end

  describe "run_suite/2" do
    test "runs tests sequentially on the local node" do
      assert {:ok, result} = CITesting.run_suite(suite(), nodes: [Node.self()], parallel: false)

      assert result.summary.total == 2
      assert result.summary.passed == 1
      assert result.summary.failed == 1
      assert result.summary.timeouts == 0
      assert %DateTime{} = result.start_time
      assert %DateTime{} = result.end_time
    end

    test "runs tests in parallel" do
      assert {:ok, result} = CITesting.run_suite(suite(), nodes: [Node.self()], parallel: true)
      assert result.summary.total == 2
    end

    test "runs setup and teardown hooks" do
      {:ok, _} =
        CITesting.run_suite(
          suite(
            setup: fn -> send(self(), :setup) end,
            teardown: fn -> send(self(), :teardown) end
          ),
          nodes: [Node.self()],
          parallel: false
        )

      assert_received :setup
      assert_received :teardown
    end

    test "handles empty test list" do
      empty = %{name: "empty", tests: [], setup: nil, teardown: nil}
      assert {:ok, result} = CITesting.run_suite(empty, nodes: [Node.self()])
      assert result.summary.total == 0
      assert result.summary.avg_duration_ms == 0
    end
  end

  describe "suite_from_modules/2" do
    test "builds a suite from modules" do
      s = CITesting.suite_from_modules("my suite", [String, Integer])
      assert s.name == "my suite"
      assert length(s.tests) == 2
      assert hd(s.tests).module == String
      assert hd(s.tests).timeout == 60_000
    end
  end

  describe "generate_ci_report/2" do
    setup do
      {:ok, result} = CITesting.run_suite(suite(), nodes: [Node.self()], parallel: false)
      {:ok, suite_result: result}
    end

    test "generates junit XML by default", %{suite_result: suite_result} do
      assert {:ok, xml} = CITesting.generate_ci_report(suite_result)
      assert xml =~ "<?xml version=\"1.0\""
      assert xml =~ "<testsuite name=\"test suite\""
      assert xml =~ "<failure"
    end

    test "generates text report", %{suite_result: suite_result} do
      assert {:ok, text} = CITesting.generate_ci_report(suite_result, format: :text)
      assert text =~ "CI Test Report: test suite"
      assert text =~ "[passed] passes"
      assert text =~ "[failed] fails"
    end

    test "generates html report", %{suite_result: suite_result} do
      assert {:ok, html} = CITesting.generate_ci_report(suite_result, format: :html)
      assert html =~ "<!DOCTYPE html>"
      assert html =~ "CI Test Report"
    end

    test "generates json report", %{suite_result: suite_result} do
      assert {:ok, json} = CITesting.generate_ci_report(suite_result, format: :json)
      assert {:ok, decoded} = JSON.decode(json)
      assert decoded["summary"]["total"] == 2
    end

    test "writes to file when :output given", %{suite_result: suite_result} do
      path = Path.join("test_tmp", "ci_report.xml")
      File.mkdir_p!(Path.dirname(path))
      on_exit(fn -> File.rm_rf!(path) end)

      assert :ok = CITesting.generate_ci_report(suite_result, output: path)
      assert File.exists?(path)
    end
  end

  describe "run_with_provisioning/2" do
    test "wraps run_suite with provisioning steps" do
      assert {:ok, result} =
               CITesting.run_with_provisioning(suite(), nodes: [Node.self()], parallel: false)

      assert result.summary.total == 2
    end
  end
end
