defmodule Mix.Tasks.Dala.Port do
  use Mix.Task

  @shortdoc "Show dala's port map per device and find host-side squatters"

  @moduledoc """
  Prints which host ports belong to which device, and flags processes that
  are squatting on them.

      mix dala.port                # table: device → dist / LV ports + status
      mix dala.port --kill         # kill any process squatting on a needed port
      mix dala.port --json         # machine-readable

  Ports covered:

    * `4369` EPMD — shared by every device on this host
    * `9100+` dist — one per device (index order matches the deployer)
    * LiveView — hashed from the app name in [4200..4999]

  A "listening" row is normal when the owning app/BEAM is alive; it's a
  problem when the owner is dead or wrong (stale iproxy, previous app
  instance). `--kill` frees those so the next deploy can bind.
  """

  @switches [
    device: :string,
    kill: :boolean,
    quiet: :boolean,
    json: :boolean
  ]

  alias DalaDev.Ports

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    DalaDev.Output.configure(quiet: opts[:quiet], json: opts[:json])

    entries =
      Ports.port_map()
      |> filter_by_device(opts[:device])
      |> Enum.map(fn entry ->
        Map.put(entry, :pids, Ports.listeners_on(entry.port))
      end)

    report(entries, opts)
  end

  # Renders the collected port map. Public test seam — takes prebuilt entries
  # so tests don't need connected devices.
  @doc false
  @spec report([map()], keyword()) :: :ok
  def report(entries, opts) do
    if entries == [] do
      DalaDev.Output.warn("No devices connected — showing nothing to map.")
    else
      if opts[:json] do
        DalaDev.Output.info(JSON.encode!(%{ports: Enum.map(entries, &entry_json/1)}))
      else
        print_table(entries)
      end

      if opts[:kill] do
        kill_squatters(entries)
      end
    end

    :ok
  end

  defp filter_by_device(entries, nil), do: entries

  defp filter_by_device(entries, id) do
    down = String.downcase(id)

    Enum.filter(entries, fn entry ->
      (entry.id && String.downcase(entry.id) == down) or
        String.downcase(entry.device) == down
    end)
  end

  @doc false
  @spec entry_json(Ports.entry()) :: %{
          device: String.t(),
          kind: String.t(),
          port: non_neg_integer(),
          node: String.t() | nil,
          listening_pids: [non_neg_integer()]
        }
  def entry_json(entry) do
    %{
      device: entry.device,
      kind: to_string(entry.kind),
      port: entry.port,
      node: entry.node && to_string(entry.node),
      listening_pids: entry.pids
    }
  end

  @doc false
  @spec print_table([map()]) :: :ok | nil
  def print_table(entries) do
    max_device = entries |> Enum.map(&String.length(&1.device)) |> Enum.max()
    max_kind = entries |> Enum.map(&(String.length(to_string(&1.kind)))) |> Enum.max()

    DalaDev.Output.info("")

    Enum.each(entries, fn entry ->
      device = String.pad_trailing(entry.device, max_device)
      kind = String.pad_trailing(to_string(entry.kind), max_kind)
      status = status_label(entry.pids)
      node = if entry.node, do: " #{entry.node}", else: ""

      DalaDev.Output.info("  #{device}  #{kind}  #{entry.port}  #{status}#{node}")
    end)

    DalaDev.Output.info("")
    DalaDev.Output.hint("--kill frees ports held by stale processes")
  end

  defp status_label([]), do: "#{IO.ANSI.faint()}free#{IO.ANSI.reset()}"

  defp status_label(pids), do: "#{IO.ANSI.yellow()}listening (pid #{Enum.join(pids, ",")})#{IO.ANSI.reset()}"

  @doc false
  @spec kill_squatters([map()]) :: :ok | nil
  def kill_squatters(entries) do
    pids = entries |> Enum.flat_map(& &1.pids) |> Enum.uniq()

    case pids do
      [] -> DalaDev.Output.info("Nothing to kill — all mapped ports are free.")
      _ -> DalaDev.Output.success("killed #{Ports.kill_pids(pids)} process(es)")
    end
  end
end
