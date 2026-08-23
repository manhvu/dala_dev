defmodule DalaDev.EnvSnapshot do
  @moduledoc """
  One-shot, machine-readable snapshot of the dala development environment.

  Answers "what do I have to work with" — toolchain versions, OTP runtime
  caches, connected devices with their node names and dist ports — in one
  call. Complements `mix dala.doctor` (which diagnoses *problems*); this is
  the neutral inventory for scripts, CI logs, and bug reports.
  """

  alias DalaDev.{Config, Device, Tunnel, Utils}
  alias DalaDev.Discovery.{Android, IOS}

  @doc """
  Collects the snapshot as a plain (JSON-encodable) map. Never raises —
  missing tools become `nil` entries. Shells out at most once per known
  toolchain command.
  """
  @spec collect() :: map()
  def collect do
    %{
      host: %{
        os: host_os(),
        elixir: System.version(),
        otp: System.otp_release(),
        developer_dir: if(macos?(), do: tool_version({"xcode-select", ["-p"]}), else: nil)
      },
      android: %{
        adb: tool_version({"adb", ["--version"]}),
        sdk_home: System.get_env("ANDROID_HOME") || System.get_env("ANDROID_SDK_ROOT"),
        emulator: tool_version({"emulator", ["-version"]})
      },
      ios: ios_section(),
      project: project_section(),
      devices: device_entries()
    }
  end

  @doc "Collects and JSON-encodes (pretty-printed)."
  @spec collect_json() :: String.t()
  def collect_json do
    JSON.encode!(collect())
  end

  # ── Version parsing (public test seams) ─────────────────────────────────────
  @doc """
  Extracts the adb platform-tools version (e.g. `"34.0.5-11300000"`).
  Handles both layouts: `Version X` on its own line (modern adb) and
  `... version X` on the banner line (older adb). The capital-V pattern runs
  first so it never grabs the older `1.x` client version from line one.
  """
  @spec parse_adb_version(String.t()) :: String.t() | nil
  def parse_adb_version(output) when is_binary(output) do
    case Regex.run(Utils.compile_regex("Version\\s+([\\w.-]+)"), output) do
      [_, version] ->
        version

      _ ->
        case Regex.run(Utils.compile_regex("version\\s+([\\w.-]+)"), output) do
          [_, version] -> version
          _ -> nil
        end
    end
  end

  def parse_adb_version(_), do: nil

  @doc "Extracts a version from `xcrun --version` output (e.g. `xcrun version 61.`)."
  @spec parse_xcrun_version(String.t()) :: String.t() | nil
  def parse_xcrun_version(output) when is_binary(output) do
    case Regex.run(Utils.compile_regex("version\\s+([\\w.]+)"), first_line(output)) do
      [_, version] -> version
      _ -> nil
    end
  end

  def parse_xcrun_version(_), do: nil

  @doc """
  Extracts the version line from `emulator -version` output, which prints
  INFO banner lines before it. Returns the trimmed line or nil.
  """
  @spec parse_emulator_version(String.t()) :: String.t() | nil
  def parse_emulator_version(output) when is_binary(output) do
    output
    |> String.split("\n")
    |> Enum.find(&(String.trim(&1) != "" and not String.starts_with?(String.trim(&1), "INFO")))
    |> case do
      nil -> nil
      line -> String.trim(line)
    end
  end

  def parse_emulator_version(_), do: nil

  # ── Internals ───────────────────────────────────────────────────────────────

  defp ios_section do
    if macos?() do
      xcrun = tool_version({"xcrun", ["--version"]})

      sim_runtimes =
        if xcrun do
          case run("xcrun", ["simctl", "list", "runtimes"]) do
            {:ok, out} ->
              out
              |> String.split("\n", trim: true)
              |> Enum.count(&String.contains?(&1, "iOS"))

            :error ->
              nil
          end
        else
          nil
        end

      %{available: true, xcrun: xcrun, ios_sim_runtimes: sim_runtimes}
    else
      %{available: false}
    end
  end

  defp project_section do
    app = Mix.Project.config()[:app]

    %{
      name: app && to_string(app),
      bundle_id: Config.bundle_id(),
      dala_exs_keys: Config.load_dala_config() |> Keyword.keys()
    }
  rescue
    _ -> %{name: nil, bundle_id: nil, dala_exs_keys: []}
  end

  defp device_entries do
    devices = Android.list_devices() ++ IOS.list_devices()

    Enum.with_index(devices, fn device, idx ->
      %{
        platform: to_string(device.platform),
        type: device.type && to_string(device.type),
        id: Device.display_id(device),
        name: device.name,
        status: to_string(device.status),
        node: device.node || to_string(Device.node_name(device)),
        dist_port: Tunnel.dist_port(idx)
      }
    end)
  end

  defp tool_version({cmd, args}) do
    if System.find_executable(cmd) do
      case run(cmd, args) do
        {:ok, out} ->
          cond do
            cmd == "adb" -> parse_adb_version(out)
            cmd == "xcrun" -> parse_xcrun_version(out)
            cmd == "emulator" -> parse_emulator_version(out)
            cmd == "xcode-select" -> String.trim(out)
            true -> first_line(out)
          end

        :error ->
          nil
      end
    else
      nil
    end
  end

  defp run(cmd, args) do
    {out, code} = System.cmd(cmd, args, stderr_to_stdout: true)

    if code == 0,
      do: {:ok, out},
      else: :error
  rescue
    _ -> :error
  end

  defp first_line(out), do: out |> String.split("\n") |> List.first()

  defp host_os do
    case :os.type() do
      {:unix, :darwin} -> "macOS"
      {:unix, os} -> to_string(os)
      {:win32, _} -> "Windows"
    end
  end

  defp macos?, do: match?({:unix, :darwin}, :os.type())
end
