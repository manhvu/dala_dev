defmodule Mix.Tasks.Dala.Env do
  use Mix.Task

  @shortdoc "Print a machine-readable snapshot of the dala dev environment"

  @moduledoc """
  One-shot inventory of your dala development environment: host toolchain
  versions, Android/iOS tool availability, project bundle id, and every
  connected device with its node name and dist port.

      mix dala.env            # human-readable summary
      mix dala.env --json     # single JSON document (scripts / CI / bug reports)

  Unlike `mix dala.doctor`, this diagnoses nothing — it's the neutral
  "what do I have" answer for scripts and issue reports.
  """

  @switches [json: :boolean, quiet: :boolean]

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    DalaDev.Output.configure(quiet: opts[:quiet], json: opts[:json])

    if opts[:json] do
      DalaDev.Output.info(DalaDev.EnvSnapshot.collect_json())
    else
      print_summary(DalaDev.EnvSnapshot.collect())
    end
  end

  # Renders the collected snapshot. Public test seam — takes a prebuilt map.
  @doc false
  @spec print_summary(map()) :: :ok
  def print_summary(snapshot) do
    host = snapshot.host

    DalaDev.Output.step("Host")
    DalaDev.Output.info("  OS      #{host.os}")
    DalaDev.Output.info("  Elixir  #{host.elixir} (OTP #{host.otp})")

    if host.developer_dir, do: DalaDev.Output.info("  Xcode   #{host.developer_dir}")

    android = snapshot.android

    DalaDev.Output.step("Android")
    print_tool("adb", android.adb)
    print_tool("emulator", android.emulator)
    print_tool("ANDROID_HOME", android.sdk_home)

    ios = snapshot.ios

    DalaDev.Output.step("iOS")

    if Map.get(ios, :available) || Map.get(ios, "available") do
      print_tool("xcrun", ios[:xcrun])

      runtimes = ios[:ios_sim_runtimes]

      if is_integer(runtimes),
        do: DalaDev.Output.info("  #{runtimes} iOS simulator runtime(s) installed")
    else
      DalaDev.Output.info("  (not available on this host)")
    end

    project = snapshot.project

    DalaDev.Output.step("Project")
    print_tool("app", project.name)
    print_tool("bundle_id", project.bundle_id)

    devices = snapshot.devices

    DalaDev.Output.step("Devices")

    case devices do
      [] ->
        DalaDev.Output.info("  (none connected)")

      _ ->
        Enum.each(devices, fn d ->
          DalaDev.Output.info(
            "  #{d.name || d.id}  #{d.id}  #{d.platform}/#{d.type}  #{d.status}  node=#{d.node} dist=#{d.dist_port}"
          )
        end)
    end

    DalaDev.Output.info("")
  end

  defp print_tool(_label, nil), do: :ok
  defp print_tool(label, value), do: DalaDev.Output.info("  #{pad(label)}#{value}")

  defp pad(label), do: String.pad_trailing(label, 14)
end
