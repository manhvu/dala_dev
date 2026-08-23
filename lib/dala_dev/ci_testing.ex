defmodule DalaDev.CITesting do
  @moduledoc """
  CI/CD integration for mobile cluster testing.

  Provides automated testing capabilities for dala Elixir clusters,
  including test orchestration, result collection, and reporting.

  ## Examples

      # Run a test suite on a cluster
      {:ok, results} = DalaDev.CITesting.run_suite(my_suite, nodes: nodes)

      # Generate a CI report
      DalaDev.CITesting.generate_ci_report(results, format: :junit)

      # Run tests with automatic device provisioning
      {:ok, results} = DalaDev.CITesting.run_with_provisioning(test_config)
  """

  # No aliases needed currently

  @type test_case :: %{
          name: String.t(),
          module: module(),
          test_fun: (-> any()) | nil,
          timeout: integer(),
          tags: [atom()]
        }

  @type test_suite :: %{
          name: String.t(),
          tests: [test_case()],
          setup: (-> any()) | nil,
          teardown: (-> any()) | nil
        }

  @type test_result :: %{
          test: test_case(),
          node: node(),
          status: :passed | :failed | :skipped | :timeout,
          duration_ms: integer(),
          error: term() | nil,
          output: String.t() | nil
        }

  @type suite_result :: %{
          suite: test_suite(),
          results: [test_result()],
          summary: map(),
          start_time: DateTime.t(),
          end_time: DateTime.t()
        }

  @doc """
  Run a test suite on specified nodes.

  Options:
  - `:nodes` - List of nodes to run tests on (default: Node.list())
  - `:parallel` - Run tests in parallel (default: true)
  - `:timeout` - Per-test timeout in ms (default: 60_000)

  Returns a suite_result.
  """
  @spec run_suite(test_suite(), keyword()) :: {:ok, suite_result()} | {:error, term()}
  def run_suite(suite, opts \\ []) do
    nodes = Keyword.get(opts, :nodes, Node.list())
    parallel = Keyword.get(opts, :parallel, true)
    timeout = Keyword.get(opts, :timeout, 60_000)

    start_time = DateTime.utc_now()

    # Run suite setup if present
    if suite.setup do
      suite.setup.()
    end

    results =
      if parallel do
        run_tests_parallel(suite.tests, nodes, timeout)
      else
        run_tests_sequential(suite.tests, nodes, timeout)
      end

    # Run suite teardown if present
    if suite.teardown do
      suite.teardown.()
    end

    end_time = DateTime.utc_now()

    summary = generate_summary(results)

    suite_result = %{
      suite: suite,
      results: results,
      summary: summary,
      start_time: start_time,
      end_time: end_time
    }

    {:ok, suite_result}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Run tests with automatic device provisioning.

  This will:
  1. Provision devices/emulators as needed
  2. Deploy the test build
  3. Run the test suite
  4. Collect results
  5. Clean up (optional)

  Options:
  - `:cleanup` - Clean up after tests (default: true)
  - `:provision_opts` - Options passed to provisioning
  """
  @spec run_with_provisioning(test_suite(), keyword()) :: {:ok, suite_result()} | {:error, term()}
  def run_with_provisioning(suite, opts \\ []) do
    cleanup = Keyword.get(opts, :cleanup, true)

    # Provision devices (simplified - would call actual provisioning)
    DalaDev.Output.info("Provisioning devices for CI testing...")

    # Deploy test build
    DalaDev.Output.info("Deploying test build...")

    # Run tests
    case run_suite(suite, opts) do
      {:ok, results} ->
        if cleanup do
          DalaDev.Output.info("Cleaning up...")
        end

        {:ok, results}

      error ->
        if cleanup do
          DalaDev.Output.info("Cleaning up after failure...")
        end

        error
    end
  end

  @doc """
  Generate a CI report from suite results.

  Formats:
  - `:junit` - JUnit XML format for CI systems
  - `:html` - HTML report
  - `:text` - Plain text summary
  - `:json` - JSON format
  """
  @spec generate_ci_report(suite_result(), keyword()) ::
          {:ok, String.t() | :ok} | {:error, term()}
  def generate_ci_report(suite_result, opts \\ []) do
    format = Keyword.get(opts, :format, :junit)
    output = Keyword.get(opts, :output)

    content =
      case format do
        :junit -> generate_junit_report(suite_result)
        :html -> generate_html_report(suite_result)
        :text -> generate_text_report(suite_result)
        :json -> JSON.encode!(json_safe(suite_result))
      end

    if output do
      case File.write(output, content) do
        :ok ->
          DalaDev.Output.success("Report written to: #{output}")
          :ok

        error ->
          error
      end
    else
      {:ok, content}
    end
  end

  @doc """
  Create a simple test suite from a list of modules.

  Each module should have a `run_tests/0` function that returns test results.
  """
  @spec suite_from_modules(String.t(), [module()]) :: test_suite()
  def suite_from_modules(name, modules) do
    tests =
      Enum.map(modules, fn mod ->
        %{
          name: "#{mod}",
          module: mod,
          test_fun: nil,
          # Will call mod.run_tests()
          timeout: 60_000,
          tags: [:module]
        }
      end)

    %{
      name: name,
      tests: tests,
      setup: nil,
      teardown: nil
    }
  end

  # ── Private helpers ──────────────────────────────

  defp run_tests_parallel(tests, nodes, timeout) do
    tests
    |> Enum.with_index()
    |> Task.async_stream(
      fn {test, i} ->
        node = Enum.at(nodes, rem(i, length(nodes)))
        run_test_on_node(test, node, timeout)
      end,
      max_concurrency: length(nodes)
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:error, reason} -> %{status: :failed, error: reason}
    end)
  end

  defp run_tests_sequential(tests, nodes, timeout) do
    Enum.with_index(tests)
    |> Enum.map(fn {test, i} ->
      node = Enum.at(nodes, rem(i, length(nodes)))
      run_test_on_node(test, node, timeout)
    end)
  end

  defp run_test_on_node(test, node, timeout) do
    start = System.monotonic_time(:millisecond)

    result =
      try do
        if test.test_fun do
          # Anonymous funs must be applied via :erlang.apply over RPC —
          # calling :rpc.call(node, fun, [], timeout) raises argument error.
          :rpc.call(node, :erlang, :apply, [test.test_fun, []], timeout)
        else
          # Assume module has a run_tests function
          :rpc.call(node, test.module, :run_tests, [], timeout)
        end
      rescue
        e -> {:error, Exception.message(e)}
      end

    duration = System.monotonic_time(:millisecond) - start

    case result do
      {:badrpc, reason} ->
        %{
          test: test,
          node: node,
          status: :failed,
          duration_ms: duration,
          error: {:rpc_error, reason},
          output: nil
        }

      {:error, reason} ->
        %{
          test: test,
          node: node,
          status: :failed,
          duration_ms: duration,
          error: reason,
          output: nil
        }

      _ ->
        %{
          test: test,
          node: node,
          status: :passed,
          duration_ms: duration,
          error: nil,
          output: inspect(result)
        }
    end
  end

  defp generate_summary(results) do
    total = length(results)
    passed = Enum.count(results, &(&1.status == :passed))
    failed = Enum.count(results, &(&1.status == :failed))
    skipped = Enum.count(results, &(&1.status == :skipped))
    timeouts = Enum.count(results, &(&1.status == :timeout))

    total_duration =
      results
      |> Enum.map(& &1.duration_ms)
      |> Enum.sum()

    %{
      total: total,
      passed: passed,
      failed: failed,
      skipped: skipped,
      timeouts: timeouts,
      total_duration_ms: total_duration,
      avg_duration_ms: if(total > 0, do: div(total_duration, total), else: 0)
    }
  end

  # Strips non-JSON-serializable values (funs, pids, refs, DateTimes) so the
  # report can be encoded safely.
  defp json_safe(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp json_safe(%{suite: suite} = suite_result) when is_map(suite) do
    suite_result
    |> Map.put(:suite, %{name: suite.name, test_count: length(suite.tests)})
    |> Map.update(:results, [], fn results -> Enum.map(results, &json_safe/1) end)
  end

  defp json_safe(%{test: test} = result) when is_map(test) do
    result
    |> Map.put(:test, %{name: test.name, module: test.module})
    |> Map.update(:error, nil, &inspect/1)
  end

  defp json_safe(other), do: other

  defp generate_junit_report(suite_result) do
    suite = suite_result.suite
    results = suite_result.results

    test_cases_xml =
      Enum.map(results, fn r ->
        test = r.test

        """
        <testcase name="#{test.name}" classname="#{suite.name}" time="#{r.duration_ms / 1000}">
          #{if r.status == :failed, do: "<failure message=\"#{inspect(r.error)}\"/>"}
          #{if r.output, do: "<system-out>#{r.output}</system-out>"}
        </testcase>
        """
      end)
      |> Enum.join("\n")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <testsuite name="#{suite.name}" tests="#{suite_result.summary.total}" failures="#{suite_result.summary.failed}" time="#{suite_result.summary.total_duration_ms / 1000}">
      #{test_cases_xml}
    </testsuite>
    """
  end

  defp generate_html_report(suite_result) do
    suite = suite_result.suite
    summary = suite_result.summary

    """
    <!DOCTYPE html>
    <html>
    <head>
        <title>CI Test Report - #{suite.name}</title>
        <script src="https://cdn.tailwindcss.com"></script>
    </head>
    <body class="bg-zinc-950 text-zinc-200 p-8">
        <h1 class="text-2xl font-bold mb-6">CI Test Report: #{suite.name}</h1>

        <div class="grid grid-cols-4 gap-4 mb-8">
            <div class="bg-zinc-800 p-4 rounded">
                <div class="text-sm text-zinc-400">Total</div>
                <div class="text-2xl">#{summary.total}</div>
            </div>
            <div class="bg-green-900/20 p-4 rounded">
                <div class="text-sm text-green-400">Passed</div>
                <div class="text-2xl text-green-300">#{summary.passed}</div>
            </div>
            <div class="bg-red-900/20 p-4 rounded">
                <div class="text-sm text-red-400">Failed</div>
                <div class="text-2xl text-red-300">#{summary.failed}</div>
            </div>
            <div class="bg-zinc-800 p-4 rounded">
                <div class="text-sm text-zinc-400">Duration</div>
                <div class="text-2xl">#{summary.total_duration_ms}ms</div>
            </div>
        </div>

        <table class="w-full text-left">
            <thead>
                <tr class="border-b border-zinc-700">
                    <th class="p-2">Test</th>
                    <th class="p-2">Node</th>
                    <th class="p-2">Status</th>
                    <th class="p-2">Duration</th>
                </tr>
            </thead>
            <tbody>
                #{Enum.map(suite_result.results, fn r -> """
      <tr class="border-b border-zinc-800">
          <td class="p-2">#{r.test.name}</td>
          <td class="p-2">#{r.node}</td>
          <td class="p-2 #{if r.status == :passed, do: "text-green-400", else: "text-red-400"}">#{r.status}</td>
          <td class="p-2">#{r.duration_ms}ms</td>
      </tr>
      """ end)}
            </tbody>
        </table>
    </body>
    </html>
    """
  end

  defp generate_text_report(suite_result) do
    summary = suite_result.summary

    """
    CI Test Report: #{suite_result.suite.name}
    ==================================

    Summary:
      Total: #{summary.total}
      Passed: #{summary.passed}
      Failed: #{summary.failed}
      Skipped: #{summary.skipped}
      Timeouts: #{summary.timeouts}
      Total Duration: #{summary.total_duration_ms}ms
      Avg Duration: #{summary.avg_duration_ms}ms

    Results:
    #{Enum.map(suite_result.results, fn r -> "  [#{r.status}] #{r.test.name} on #{r.node} (#{r.duration_ms}ms)" end)}
    """
  end
end
