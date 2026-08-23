defmodule DalaDev.Server.ObserverEtsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint DalaDev.Server.Endpoint

  # A uniquely named ETS table so filtering has a deterministic needle in the
  # real local table list.
  @probe_table :zebra_table_probe_unique

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
    if :ets.whereis(@probe_table) == :undefined do
      parent = self()

      {:ok, _keeper} =
        Task.start_link(fn ->
          :ets.new(@probe_table, [:named_table, :public])
          send(parent, :ready)
          Process.sleep(:infinity)
        end)

      receive do
        :ready -> :ok
      after
        1_000 -> flunk("probe table was not created")
      end
    end

    :ok
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  # Atom.to_string (not inspect) — dotted node names would otherwise be
  # inspected as :"name@127.0.0.1", leaving quote characters in the URL param.
  defp node_param, do: Atom.to_string(Node.self())

  defp ets_path(conn), do: live(conn, "/observer/#{node_param()}/ets")

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

  # Parses the "N / M tables" counter shown above the table.
  defp counts(view) do
    html = render(element(view, "span", "tables"))

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

  # Parses rendered numbers: "12", "1.2K", "5.0M", "812 B".
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

  # Rendered values round across unit boundaries ("1023" vs "1.0K"), so allow
  # tolerance when checking ordering.
  defp order_violations(values, direction) do
    values
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [prev, cur] -> violated?(prev, cur, direction) end)
  end

  defp violated?(prev, cur, :desc), do: cur > prev * 1.06 + 64
  defp violated?(prev, cur, :asc), do: cur < prev * 0.94 - 64

  # ── Tests ────────────────────────────────────────────────────────────────────

  describe "mount/3" do
    test "fetches the local ETS tables sorted by memory desc", %{conn: conn} do
      {:ok, view, _html} = ets_path(conn)
      assert has_element?(view, "h1", "ETS Tables:")
      wait_until_loaded(view)

      {filtered, _total} = counts(view)
      assert filtered > 0
      assert filtered <= 100

      assert order_violations(column_values(view, 4), :desc) == []
      refute has_element?(view, ".text-red-400")
    end
  end

  describe "sorting" do
    # NOTE: unlike the processes view, no ETS column header carries a
    # phx-click="sort" hook, so these drive the sort event directly.
    test "re-clicking the active column toggles desc to asc", %{conn: conn} do
      {:ok, view, _html} = ets_path(conn)
      wait_until_loaded(view)

      # the view mounts sorted by memory desc; the first click flips to asc
      render_click(view, "sort", %{"by" => "memory"})
      assert order_violations(column_values(view, 4), :asc) == []

      render_click(view, "sort", %{"by" => "memory"})
      assert order_violations(column_values(view, 4), :desc) == []
    end

    test "\"sort\" by size orders the size column descending", %{conn: conn} do
      {:ok, view, _html} = ets_path(conn)
      wait_until_loaded(view)

      html = render_click(view, "sort", %{"by" => "size"})
      refute html =~ "Invalid node"

      assert order_violations(column_values(view, 3), :desc) == []
    end

    test "unknown column keeps the tables listed without sort indicators", %{conn: conn} do
      {:ok, view, _html} = ets_path(conn)
      wait_until_loaded(view)

      html = render_click(view, "sort", %{"by" => "bogus"})
      refute html =~ "↓"
      refute html =~ "↑"

      {_filtered, total} = counts(view)
      assert total > 0
    end
  end

  describe "filtering" do
    test "filters down to the matching table", %{conn: conn} do
      {:ok, view, _html} = ets_path(conn)
      wait_until_loaded(view)

      html = render_change(view, "filter", %{"filter" => Atom.to_string(@probe_table)})

      assert html =~ "1 / "
      assert html =~ Atom.to_string(@probe_table)
    end

    test "empty filter restores all tables", %{conn: conn} do
      {:ok, view, _html} = ets_path(conn)
      wait_until_loaded(view)

      render_change(view, "filter", %{"filter" => Atom.to_string(@probe_table)})
      render_change(view, "filter", %{"filter" => ""})

      {filtered, total} = counts(view)
      # the visible list is capped at the page size of 100
      assert filtered == min(total, 100)
      assert filtered > 0
    end
  end

  describe "selection" do
    test "clicking a row highlights it as selected", %{conn: conn} do
      {:ok, view, _html} = ets_path(conn)
      wait_until_loaded(view)

      render_change(view, "filter", %{"filter" => Atom.to_string(@probe_table)})

      row_html =
        view
        |> element("tbody tr")
        |> render_click()

      assert row_html =~ "bg-zinc-800"
    end
  end

  describe "handle_info/2 and handle_params/3" do
    test ":refresh refetches without surfacing an error", %{conn: conn} do
      {:ok, view, _html} = ets_path(conn)
      wait_until_loaded(view)

      send(view.pid, :refresh)
      wait_until_loaded(view)

      refute has_element?(view, ".text-red-400")
    end

    test "unknown node sets an error instead of crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/observer/no_such_node_xyz/ets")

      assert has_element?(view, ".text-red-400", "Invalid node name")
    end
  end
end
