defmodule DalaDev.Tui.Devices do
  @moduledoc """
  Device discovery and status for the TUI.

  Wraps `DalaDev.Discovery.Android` and `DalaDev.Discovery.IOS` to provide
  a unified device list with rich status information including node
  connectivity, distribution ports, and remote node metadata.
  """

  defstruct [
    :id,
    :platform,
    :type,
    :name,
    :status,
    :serial,
    :version,
    :node,
    :dist_port,
    :host_ip,
    :error,
    :device_struct
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          platform: :android | :ios,
          type: :device | :emulator | :simulator | :physical,
          name: String.t(),
          status: :discovered | :unauthorized | :tunneled | :connected | :error,
          serial: String.t() | nil,
          version: String.t() | nil,
          node: atom() | nil,
          dist_port: pos_integer() | nil,
          host_ip: String.t() | nil,
          error: String.t() | nil,
          device_struct: map() | nil
        }

  @doc """
  Lists all discovered devices across Android and iOS.

  Returns a list of `%DalaDev.Tui.Devices{}` structs with rich metadata.
  """
  @spec list() :: [t()]
  def list do
    (list_android() ++ list_ios() ++ list_connected_nodes())
    |> Enum.sort_by(& &1.name)
    |> Enum.uniq_by(& &1.id)
  end

  @doc """
  Lists Android devices via ADB.
  """
  @spec list_android() :: [t()]
  def list_android do
    DalaDev.Discovery.Android.list_devices()
    |> Enum.map(&from_device/1)
  end

  @doc """
  Lists iOS devices and simulators.
  """
  @spec list_ios() :: [t()]
  def list_ios do
    DalaDev.Discovery.IOS.list_devices()
    |> Enum.map(&from_device/1)
  end

  @doc """
  Converts a `%DalaDev.Device{}` into a TUI device entry.

  Public for testing.
  """
  @spec from_device(DalaDev.Device.t()) :: t()
  def from_device(%DalaDev.Device{} = device) do
    %__MODULE__{
      id: device.serial,
      platform: device.platform,
      type: device.type || :device,
      name: device.name || device.serial,
      status: normalize_status(device.status),
      serial: device.serial,
      version: device.version,
      node: device.node,
      dist_port: device.dist_port,
      host_ip: device.host_ip,
      error: device.error,
      device_struct: device
    }
  end

  @doc """
  Lists nodes connected via Erlang distribution that aren't already
  in the discovered device list.
  """
  @spec list_connected_nodes() :: [t()]
  def list_connected_nodes do
    connected_ids = MapSet.new(list_android() ++ list_ios(), & &1.id)

    Node.list(:connected)
    |> Enum.filter(fn node ->
      node_name = Atom.to_string(node)
      # Only include dala-related nodes
      String.contains?(node_name, "dala") and
        not MapSet.member?(connected_ids, node_name)
    end)
    |> Enum.map(fn node ->
      node_str = Atom.to_string(node)
      # Parse platform from node name convention: dala_app_android_serial@host
      {platform, type} = parse_node_platform(node_str)
      name = parse_node_name(node_str)

      %__MODULE__{
        id: node_str,
        platform: platform,
        type: type,
        name: name,
        status: :connected,
        serial: nil,
        version: nil,
        node: node,
        dist_port: nil,
        host_ip: nil,
        error: nil,
        device_struct: nil
      }
    end)
  end

  @doc """
  Gets the node name for a device using DalaDev.Device conventions.
  """
  @spec node_name(t()) :: atom() | nil
  # Note: `is_atom(nil)` is true in Elixir, so we must exclude nil explicitly
  def node_name(%__MODULE__{node: node}) when is_atom(node) and not is_nil(node), do: node

  def node_name(%__MODULE__{platform: :android, serial: serial, name: name}) do
    suffix =
      if serial,
        do: String.downcase(serial),
        else: String.downcase(name) |> String.replace(" ", "_")

    "dala_app_android_#{suffix}" |> String.to_atom()
  end

  def node_name(%__MODULE__{platform: :ios, serial: serial, name: name}) do
    suffix =
      if serial,
        do: String.downcase(serial),
        else: String.downcase(name) |> String.replace(" ", "_")

    "dala_app_ios_#{suffix}" |> String.to_atom()
  end

  @doc """
  Returns a short display name for a device.
  """
  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{name: name, type: type}) do
    type_str =
      case type do
        :emulator -> "emulator"
        :simulator -> "simulator"
        :physical -> "physical"
        :device -> "device"
      end

    "#{name} (#{type_str})"
  end

  @doc """
  Returns the status icon for a device.
  """
  @spec status_icon(t()) :: String.t()
  def status_icon(%__MODULE__{status: :connected}), do: "🟢"
  def status_icon(%__MODULE__{status: :tunneled}), do: "🟡"
  def status_icon(%__MODULE__{status: :discovered}), do: "⚪"
  def status_icon(%__MODULE__{status: :unauthorized}), do: "🔴"
  def status_icon(%__MODULE__{status: :error}), do: "❌"
  def status_icon(_), do: "❓"

  @doc """
  Returns the platform icon.
  """
  @spec platform_icon(t()) :: String.t()
  def platform_icon(%__MODULE__{platform: :android}), do: "🤖"
  def platform_icon(%__MODULE__{platform: :ios}), do: "🍎"
  def platform_icon(_), do: "📱"

  @doc """
  Returns a human-readable status label.
  """
  @spec status_label(t()) :: String.t()
  def status_label(%__MODULE__{status: :connected}), do: "connected"
  def status_label(%__MODULE__{status: :tunneled}), do: "tunneled"
  def status_label(%__MODULE__{status: :discovered}), do: "discovered"
  def status_label(%__MODULE__{status: :unauthorized}), do: "unauthorized"
  def status_label(%__MODULE__{status: :error}), do: "error"
  def status_label(%__MODULE__{status: status}), do: Atom.to_string(status)

  @doc """
  Returns a one-line summary of the device.
  """
  @spec summary(t()) :: String.t()
  def summary(%__MODULE__{} = device) do
    base = "#{platform_icon(device)} #{display_name(device)} — #{status_label(device)}"

    extra =
      case device do
        %{node: node} when is_atom(node) and not is_nil(node) -> " | node: #{node}"
        %{dist_port: port} when is_integer(port) -> " | port: #{port}"
        %{host_ip: ip} when is_binary(ip) -> " | ip: #{ip}"
        _ -> ""
      end

    base <> extra
  end

  # ── Private ──────────────────────────────────────────────────

  defp normalize_status(:connected), do: :connected
  defp normalize_status(:disconnected), do: :discovered
  defp normalize_status(:offline), do: :discovered
  defp normalize_status(:ok), do: :connected
  defp normalize_status(nil), do: :discovered
  defp normalize_status(status) when is_atom(status), do: status
  defp normalize_status(_), do: :discovered

  defp parse_node_platform(node_name) do
    cond do
      String.contains?(node_name, "android") -> {:android, :device}
      String.contains?(node_name, "ios") -> {:ios, :device}
      true -> {:unknown, :device}
    end
  end

  defp parse_node_name(node_name) do
    node_name
    |> String.split("_")
    |> Enum.drop_while(&(&1 != "android" and &1 != "ios"))
    |> case do
      [platform | rest] -> Enum.join([platform] ++ rest, " ")
      [] -> node_name
    end
  end
end
