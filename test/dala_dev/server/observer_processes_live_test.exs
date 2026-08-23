defmodule DalaDev.Server.ObserverProcessesLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint DalaDev.Server.Endpoint

  # A uniquely named process so filtering has a deterministic needle in the
  # real local process list.
  @probe_name "zebra_probe_unique_9x7"

  setup_all do
    case start_supervised({Phoenix.PubSub, name: DalaDev.PubSub}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Application.put_env(:dala_dev, DalaDev.Server.Endpoint,
      server: false,
      live_view: [signing_salt: "dala_dev"],
      secret_key_base: String.duplicate("a", 64),
      render_errors: [view: DalaDev.ErrorView, accepts: ~w(html)],
      pubsub_server: DalaDev.PubSub,
      url: [host: "localhost"],
      render_on_error: false
    )

    start_supervised!(DalaDev.Server.Endpoint)

    {:ok, conn: build_conn()}
  end

  setup do
    name = String.to_atom(@probe_name)

    if Process.whereis(name) == nil do
      {:ok, pid} = Task.start_link(fn -> Process.sleep(:infinity) end)
      Process.register(pid, name)
    end

    :ok
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  # Atom.to_string (not inspect) — dotted node names would otherwise be
  # inspected as :"name@127.0.0.1", leaving quote characters in the URL param.
  defp node_param, do: Atom.to_string(Node.self())

  defp processes_path(conn), do: live(conn, "/observer/#{node_param()}/processes")

  defp eventually(fun, tries \\ 100)

  defp eventually(_fun, 0), do: flunk("condition not met")

  defp eventually(fun, tries) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      eventually(fun, tries - 1)
    end
  end

  defp wait_until_loaded(view) do
    eventually(fn ->
      {_filtered, total} = counts(view)
      total > 0
    end)
  end

  # Parses the "N / M processes" counter shown above the table.
  defp counts(view) do
    html = render(element(view, "span", "processes"))

    [filtered, total] =
      Regex.run(Regex.compile!("(\\d+) / (\\d+)"), html, capture: :all_but_first)
      |> Enum.map(&String.to_integer/1)

    {filtered, total}
  end

  defp row_cells(view) do
    tbody = render(element(view, "tbody"))

    Regex.scan(Regex.compile!("<tr[^>]*>(.*?)</tr>", "s"), tbody, capture: :all_but_first)
    |> Enum.map(fn [row] ->
      Regex.scan(Regex.compile!("<td[^>]*>(.*?)</td>", "s"), row, capture: :all_but_first)
      |> List.flatten()
    end)
  end

  defp column_values(view, index),
    do: row_cells(view) |> Enum.map(&parse_number(Enum.at(&1, index)))

  # Parses rendered numbers: "812", "12.3K", "1.5M", "812 B", "1.2 MB".
  defp parse_number(cell) do
    case Regex.run(Regex.compile!("^([\\d.]+)\\s*([KMG]?)B?$"), String.trim(cell),
           capture: :all_but_first
         ) do
      [num, unit] ->
        {value, _} = Float.parse(num)
        trunc(value * unit_multiplier(unit))

      _ ->
        0
    end
  end

  defp unit_multiplier(""), do: 1
  defp unit_multiplier("K"), do: 1_000
  defp unit_multiplier("M"), do: 1_000_000
  defp unit_multiplier("G"), do: 1_000_000_000

  # Rendered values are lossy: unit-boundary rounding ("1023" vs "1.0K") and
  # zero-collapsing ("0.0 GB"), so skip zero cells and allow tolerance.
  defp order_violations(values, direction) do
    values
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [prev, cur] ->
      prev != 0 and cur != 0 and violated?(prev, cur, direction)
    end)
  end

  defp violated?(prev, cur, :desc), do: cur > prev * 1.06 + 64
  defp violated?(prev, cur, :asc), do: cur < prev * 0.94 - 64

  # ── Tests ────────────────────────────────────────────────────────────────────

  describe "mount/3" do
    test "fetches the local process list sorted by memory desc", %{conn: conn} do
      {:ok, view, _html} = processes_path(conn)
      assert has_element?(view, "h1", "Processes:")
      wait_until_loaded(view)

      {filtered, _total} = counts(view)
      assert filtered > 0
      # capped at the page size of 100
      assert filtered <= 100

      assert order_violations(column_values(view, 2), :desc) == []

      refute has_element?(view, ".text-red-400")
    end
  end

  describe "sorting" do
    test "re-clicking the active column toggles desc to asc", %{conn: conn} do
      {:ok, view, _html} = processes_path(conn)
      wait_until_loaded(view)

      assert render(element(view, "th[phx-value-by='memory']")) =~ "↓"

      view |> element("th[phx-value-by='memory']") |> render_click(%{})

      assert render(element(view, "th[phx-value-by='memory']")) =~ "↑"
      assert order_violations(column_values(view, 2), :asc) == []
    end

    test "switching columns resets to desc", %{conn: conn} do
      {:ok, view, _html} = processes_path(conn)
      wait_until_loaded(view)

      # flip the default memory column to asc first
      view |> element("th[phx-value-by='memory']") |> render_click(%{})
      assert render(element(view, "th[phx-value-by='memory']")) =~ "↑"

      # switching columns starts over at desc
      view |> element("th[phx-value-by='reductions']") |> render_click(%{})
      assert render(element(view, "th[phx-value-by='reductions']")) =~ "↓"
      refute render(element(view, "th[phx-value-by='memory']")) =~ "↑"
      assert order_violations(column_values(view, 3), :desc) == []

      # and a second click of the new column toggles back up
      view |> element("th[phx-value-by='reductions']") |> render_click(%{})
      assert render(element(view, "th[phx-value-by='reductions']")) =~ "↑"
      assert order_violations(column_values(view, 3), :asc) == []
    end
  end

  describe "filtering" do
    test "filters down to the matching registered process", %{conn: conn} do
      {:ok, view, _html} = processes_path(conn)
      wait_until_loaded(view)

      html = render_change(view, "filter", %{"filter" => @probe_name})

      assert html =~ "1 / "
      assert html =~ @probe_name
    end

    test "empty filter restores all processes", %{conn: conn} do
      {:ok, view, _html} = processes_path(conn)
      wait_until_loaded(view)

      render_change(view, "filter", %{"filter" => @probe_name})
      render_change(view, "filter", %{"filter" => ""})

      {filtered, total} = counts(view)
      # the visible list is capped at the page size of 100
      assert filtered == min(total, 100)
      assert filtered > 0
    end
  end

  describe "selection" do
    test "clicking a row opens its details modal and closing hides it", %{conn: conn} do
      {:ok, view, _html} = processes_path(conn)
      wait_until_loaded(view)

      # narrow to the probe process so the table holds exactly one row
      render_change(view, "filter", %{"filter" => @probe_name})

      view |> element("tbody tr") |> render_click()

      assert has_element?(view, "h2", "Process Details")
      assert has_element?(view, "dd", @probe_name)

      view |> element("button", "Close") |> render_click()

      refute has_element?(view, "h2", "Process Details")
    end
  end

  describe "handle_info/2 and handle_params/3" do
    test ":refresh refetches without surfacing an error", %{conn: conn} do
      {:ok, view, _html} = processes_path(conn)
      wait_until_loaded(view)

      send(view.pid, :refresh)
      wait_until_loaded(view)

      refute has_element?(view, ".text-red-400")
    end

    test "unknown node sets an error instead of crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer/no_such_node_xyz/processes")

      assert has_element?(view, ".text-red-400", "Invalid node name")
    end
  end
end
