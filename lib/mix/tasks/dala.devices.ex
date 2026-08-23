defmodule Mix.Tasks.Dala.Devices do
  use Mix.Task

  @shortdoc "List all connected Android and iOS devices"

  @moduledoc """
  Scans for connected Android devices (via adb) and iOS simulators/physical
  devices (via xcrun simctl / ideviceinfo) and prints their status.

      mix dala.devices

  Each device is shown with a short **ID** you can pass to `--device`:

      mix dala.deploy --device emulator-5554
      mix dala.deploy --native --device 78354490

  Gracefully skips platforms whose tools are not installed (adb / xcrun).

  ## Under the hood

      # Android
      adb devices -l
      # → parses serial numbers, device/emulator state, and manufacturer/model

      # iOS (macOS only)
      xcrun simctl list devices booted --json
      ideviceinfo -k UniqueDeviceID   (if libimobiledevice is installed)
  """

  alias DalaDev.Discovery.{Android, IOS}
  alias DalaDev.Device

  @impl Mix.Task
  def run(_args) do
    DalaDev.Output.configure([])
    Mix.Task.run("app.config")

    android = list_android()
    ios = list_ios()

    DalaDev.Output.info("")
    print_section("Android", android)
    DalaDev.Output.info("")
    print_section("iOS", ios)

    all = device_list(android) ++ device_list(ios)

    if all != [] do
      DalaDev.Output.info("")
      DalaDev.Output.hint("Pass the ID to --device to target a specific device:")
      DalaDev.Output.info("  mix dala.deploy --device #{Device.display_id(hd(all))}")

      print_bench_hints(all)
    end

    DalaDev.Output.info("")
  end

  defp print_bench_hints(all) do
    physical_ios_with_ip =
      Enum.find(all, fn d ->
        d.platform == :ios and d.type == :physical and d.host_ip
      end)

    physical_android =
      Enum.find(all, fn d -> d.platform == :android and d.type == :physical end)

    if physical_ios_with_ip do
      DalaDev.Output.info("")
      DalaDev.Output.info("For an iOS battery bench, use --wifi-ip with the device IP:")

      DalaDev.Output.info("  mix dala.battery_bench_ios --no-build --wifi-ip #{physical_ios_with_ip.host_ip}")
    end

    if physical_android do
      DalaDev.Output.info("")
      DalaDev.Output.info("For an Android battery bench, target the device by serial:")

      DalaDev.Output.info(
        "  mix dala.battery_bench_android --no-build --device #{physical_android.serial}"
      )
    end
  end

  # ── Device discovery (returns tagged list or a reason atom) ──────────────────

  defp list_android do
    case System.find_executable("adb") do
      nil -> {:unavailable, "adb not found — install Android platform-tools"}
      _ -> {:ok, Android.list_devices()}
    end
  end

  defp list_ios do
    cond do
      not macos?() ->
        {:unavailable, "iOS deployment requires macOS"}

      System.find_executable("xcrun") == nil ->
        {:unavailable, "xcrun not found — install Xcode command-line tools"}

      true ->
        {:ok, IOS.list_devices()}
    end
  end

  # ── Output ───────────────────────────────────────────────────────────────────

  defp print_section(title, result) do
    DalaDev.Output.step(title)

    case result do
      {:unavailable, reason} ->
        DalaDev.Output.warn("(#{reason})")

      {:ok, []} ->
        DalaDev.Output.info("  (none)")

      {:ok, devices} ->
        print_table(devices)
        Enum.each(devices, &print_hints/1)
    end
  end

  defp print_table(devices) do
    max_name = devices |> Enum.map(&name_len/1) |> Enum.max()
    max_ver = devices |> Enum.map(&ver_len/1) |> Enum.max()
    max_type = devices |> Enum.map(&type_len/1) |> Enum.max()
    max_id = devices |> Enum.map(&id_len/1) |> Enum.max()
    any_ip = Enum.any?(devices, & &1.host_ip)

    Enum.each(devices, fn d ->
      icon = status_icon(d)
      name = pad(d.name || d.serial, max_name)
      ver = pad(d.version || "", max_ver)
      type = pad(type_label(d), max_type)

      id = pad(Device.display_id(d), max_id)

      ip_part =
        cond do
          d.host_ip -> "  #{d.host_ip}"
          any_ip -> "  (no IP)"
          true -> ""
        end

      DalaDev.Output.info("  #{icon}  #{name}  #{ver}  #{type}  #{id}#{ip_part}")
    end)
  end

  defp name_len(d), do: String.length(d.name || d.serial)
  defp ver_len(d), do: String.length(d.version || "")
  defp type_len(d), do: String.length(type_label(d))
  defp id_len(d), do: String.length(Device.display_id(d))

  defp type_label(%{type: :emulator}), do: "emulator"
  defp type_label(%{type: :simulator}), do: "simulator"
  defp type_label(%{type: :physical}), do: "physical"
  defp type_label(_), do: "device"

  defp status_icon(%{status: :connected}), do: "✓"
  defp status_icon(%{status: :booted}), do: "·"
  defp status_icon(%{status: :discovered}), do: "·"
  defp status_icon(%{status: :unauthorized}), do: "✗"
  defp status_icon(%{status: :error}), do: "!"
  defp status_icon(_), do: "·"

  defp pad(str, width), do: String.pad_trailing(str, width)

  # ── Hints ────────────────────────────────────────────────────────────────────

  defp print_hints(%{status: :unauthorized}) do
    DalaDev.Output.warn("→ Check device for 'Allow USB debugging?' prompt")
  end

  defp print_hints(%{platform: :android, serial: serial}) do
    case Android.developer_mode(serial) do
      :disabled ->
        DalaDev.Output.warn("→ Enable Developer Mode: Settings → About → tap Build Number 7×")

      _ ->
        :ok
    end
  end

  defp print_hints(_), do: :ok

  defp device_list({:ok, devices}), do: devices
  defp device_list({:unavailable, _}), do: []

  defp macos?, do: match?({:unix, :darwin}, :os.type())
end
