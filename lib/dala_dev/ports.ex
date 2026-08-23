defmodule DalaDev.Ports do
  @moduledoc """
  Maps dala's per-device ports and finds host-side squatters.

  Two failure modes this makes visible:

    * A stale process (old iproxy, leftover dev server, a previous app
      instance) is already listening on a port the next device needs.
    * You can't remember which dist/LV port belongs to which device when
      something misbehaves.

  Port model:

    * EPMD — 4369, shared by all devices on the host
    * dist — `Tunnel.dist_port(index)` (9100 + index) per discovered device,
      using the same index order as the deployer/connector
    * LiveView — hashed from the app name in [4200..4999], matching the
      hash-based port allocation in `Dala.LiveView.local_url/1`
  """

  alias DalaDev.{Device, Tunnel}
  alias DalaDev.Discovery.{Android, IOS}

  @epmd_port 4369

  @typedoc "One expected port binding: which device uses it and for what."
  @type entry :: %{
          required(:device) => String.t(),
          required(:id) => String.t() | nil,
          required(:kind) => :epmd | :dist | :liveview,
          required(:port) => non_neg_integer(),
          required(:node) => atom() | nil
        }

  @doc """
  Builds the expected port map for currently connected devices. Android
  devices come first (deployer index order), then iOS.

  `lister/0` overrides discovery (test seam — mirrors
  `NativeBuild.narrow_platforms_for_device/3`).
  """
  @spec port_map((-> [Device.t()])) :: [entry()]
  def port_map(lister \\ &default_lister/0) do
    devices = lister.()

    epmd_entries =
      if devices == [] do
        []
      else
        [
          %{
            device: "(all devices)",
            id: nil,
            kind: :epmd,
            port: @epmd_port,
            node: nil
          }
        ]
      end

    device_entries =
      devices
      |> Enum.with_index()
      |> Enum.flat_map(fn {device, idx} ->
        label = device.name || device.serial
        dist = Tunnel.dist_port(idx)

        [
          %{
            device: label,
            id: Device.display_id(device),
            kind: :dist,
            port: dist,
            node: node_for(device)
          },
          %{
            device: label,
            id: Device.display_id(device),
            kind: :liveview,
            port: liveview_port(),
            node: nil
          }
        ]
      end)

    epmd_entries ++ device_entries
  end

  @doc """
  Expected LiveView port for this project — same formula as dala's hash-based
  default (`4200 + rem(phash2(app_name), 800)`). Public for testing.
  """
  @spec liveview_port() :: non_neg_integer()
  def liveview_port do
    app_name = Mix.Project.config()[:app] |> to_string()
    4200 + rem(:erlang.phash2(app_name), 800)
  end

  @doc """
  Returns pids of host processes listening on `port`, as integers.
  Empty list means the port is free. Uses `lsof` (macOS/Linux).
  """
  @spec listeners_on(non_neg_integer()) :: [non_neg_integer()]
  def listeners_on(port) do
    case System.cmd("lsof", ["-ti", "tcp:#{port}"], stderr_to_stdout: true) do
      {out, 0} ->
        out
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.map(&Integer.parse/1)
        |> Enum.map(fn
          {pid, _} -> pid
          :error -> nil
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      _ ->
        []
    end
  end

  @doc """
  Kills the given host PIDs with SIGKILL. Returns count actually signalled.
  """
  @spec kill_pids([non_neg_integer()]) :: non_neg_integer()
  def kill_pids(pids) do
    Enum.count(pids, fn pid ->
      match?({_, 0}, System.cmd("kill", ["-9", to_string(pid)], stderr_to_stdout: true))
    end)
  end

  # ── Internals ───────────────────────────────────────────────────────────────

  defp default_lister, do: Android.list_devices() ++ IOS.list_devices()

  # Node names only make sense for devices whose BEAM we can name; keep it
  # best-effort so the map still renders when discovery lacks metadata.
  defp node_for(%Device{} = d), do: Device.node_name(d)
end
