defmodule DalaDev.Bench.ADBHelper do
  @moduledoc """
  Common ADB operations for battery benchmarking.

  Centralizes ADB command execution to reduce duplication across
  battery bench and preflight modules.
  """

  # Compiled at module-attribute expansion time via
  # `DalaDev.Utils.compile_regex/2` (compile-time regex sigil literals are unsafe
  # on Elixir 1.19 / OTP 28.0+).
  @battery_level_pattern DalaDev.Utils.compile_regex("^\\s*level:\\s*(\\d+)", "m")
  @wifi_ip_pattern DalaDev.Utils.compile_regex(
                     "\\bsrc\\s+(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})"
                   )

  @doc """
  Checks if ADB is available and a device is reachable.

  Returns `{:ok, serial}` if a device is found, `{:error, reason}` otherwise.
  """
  @spec check_device(String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  def check_device(nil) do
    case System.find_executable("adb") do
      nil -> {:error, "adb not found (install Android platform-tools)"}
      _ -> check_any_device()
    end
  end

  def check_device(serial) when is_binary(serial) do
    case System.find_executable("adb") do
      nil -> {:error, "adb not found (install Android platform-tools)"}
      _ -> check_specific_device(serial)
    end
  end

  defp check_any_device do
    case System.cmd("adb", ["devices"], stderr_to_stdout: true) do
      {out, 0} ->
        devices =
          out
          |> String.split("\n")
          |> Enum.drop(1)
          |> Enum.flat_map(fn line ->
            case String.split(line) do
              [s, "device" | _] -> [s]
              _ -> []
            end
          end)

        case devices do
          [] -> {:error, "no Android device detected (adb devices returned empty)"}
          [single] -> {:ok, "device connected: #{single}"}
          many -> {:ok, "#{length(many)} devices connected"}
        end

      _ ->
        {:error, "adb devices failed"}
    end
  end

  defp check_specific_device(serial) do
    case System.cmd("adb", ["-s", serial, "get-state"], stderr_to_stdout: true) do
      {out, 0} ->
        state = String.trim(out)

        if state == "device",
          do: {:ok, "adb device #{serial} (#{state})"},
          else: {:error, "adb device #{serial} state: #{state}"}

      {out, _} ->
        {:error, "adb get-state failed: #{String.trim(out)}"}
    end
  end

  @doc """
  Checks if an app is installed on an Android device.
  """
  @spec check_app_installed(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def check_app_installed(serial, bundle) do
    case System.cmd("adb", ["-s", serial, "shell", "pm", "list", "packages", bundle],
           stderr_to_stdout: true
         ) do
      {out, 0} ->
        if String.contains?(out, "package:#{bundle}") do
          {:ok, "#{bundle} installed on device"}
        else
          {:error, "#{bundle} not installed — run `mix dala.deploy --native`"}
        end

      {out, _} ->
        {:error, "adb pm list failed: #{String.trim(out)}"}
    end
  end

  @doc """
  Runs an ADB command and returns the output.
  """
  @spec run(String.t(), [String.t()]) :: {:ok, String.t()} | {:error, String.t()}
  def run(serial, args) do
    case System.cmd("adb", ["-s", serial | args], stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, _} -> {:error, String.trim(out)}
    end
  end

  @doc """
  Runs an ADB command and returns the raw output (including stderr).
  """
  @spec run_raw(String.t(), [String.t()]) :: String.t()
  def run_raw(serial, args) do
    {out, _} = System.cmd("adb", ["-s", serial | args], stderr_to_stdout: true)
    out
  end

  @doc """
  Checks if ADB is available.
  """
  @spec available?() :: boolean()
  def available? do
    System.find_executable("adb") != nil
  end

  @doc """
  Gets the battery level from an Android device.
  """
  @spec battery_level(String.t()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def battery_level(serial) do
    case System.cmd("adb", ["-s", serial, "shell", "dumpsys", "battery"], stderr_to_stdout: true) do
      {out, 0} ->
        case Regex.run(@battery_level_pattern, out) do
          [_, n_str] ->
            case Integer.parse(n_str) do
              {n, _} when n in 0..100 -> {:ok, n}
              _ -> {:error, "adb battery: bad level value #{n_str}"}
            end

          nil ->
            {:error, "adb battery: no level field in dumpsys output"}
        end

      {out, _} ->
        {:error, "adb battery: " <> String.trim(out)}
    end
  rescue
    e -> {:error, "adb raised: #{Exception.message(e)}"}
  end

  @doc """
  Gets the PID of an app on an Android device.
  """
  @spec app_pid(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()} | :app_dead
  def app_pid(serial, bundle) do
    case System.find_executable("adb") do
      nil ->
        :app_unknown

      _ ->
        case System.cmd("adb", ["-s", serial, "shell", "pidof", bundle], stderr_to_stdout: true) do
          {out, 0} ->
            case String.trim(out) do
              "" ->
                :app_dead

              pid_str ->
                case Integer.parse(pid_str) do
                  {n, _} when n > 0 -> {:ok, pid_str}
                  _ -> :app_dead
                end
            end

          _ ->
            :app_dead
        end
    end
  rescue
    _ -> :app_unknown
  end

  @doc """
  Checks if a device is reachable via ADB.
  """
  @spec device_ok?(String.t()) :: boolean()
  def device_ok?(%DalaDev.Device{serial: serial}), do: device_ok?(serial)

  def device_ok?(serial) when is_binary(serial) do
    case System.cmd("adb", ["-s", serial, "shell", "echo", "ok"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc """
  Enables WiFi ADB for a device.
  """
  @spec enable_wifi_adb(String.t()) :: :ok | {:error, String.t()}
  def enable_wifi_adb(serial) do
    case System.cmd("adb", ["-s", serial, "tcpip", "5555"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, _} -> {:error, String.trim(out)}
    end
  end

  @doc """
  Gets the WiFi IP for a device.
  """
  @spec wifi_ip(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def wifi_ip(serial) do
    case System.cmd("adb", ["-s", serial, "shell", "ip", "route", "get", "1.1.1.1"],
           stderr_to_stdout: true
         ) do
      {out, 0} ->
        case Regex.run(@wifi_ip_pattern, out) do
          [_, ip] -> {:ok, ip}
          _ -> {:error, "could not determine device IP"}
        end

      {out, _} ->
        {:error, String.trim(out)}
    end
  end

  @doc """
  Sets up ADB tunnels for device communication.
  """
  @spec setup_tunnels(String.t()) :: :ok
  def setup_tunnels(serial) when is_binary(serial) do
    System.cmd("adb", ["-s", serial, "reverse", "tcp:4369", "tcp:4369"], stderr_to_stdout: true)
    System.cmd("adb", ["-s", serial, "forward", "tcp:9100", "tcp:9100"], stderr_to_stdout: true)
    :ok
  end

  @doc """
  Ensures local Erlang distribution is started.
  """
  @spec ensure_local_dist() :: :ok
  def ensure_local_dist do
    unless Node.alive?() do
      Node.start(:"dala_bench_android@127.0.0.1", :longnames)
      Node.set_cookie(:dala_secret)
    end

    :ok
  end

  @doc """
  Auto-detects a connected Android device.
  """
  @spec auto_detect_device() :: String.t() | nil
  def auto_detect_device do
    case System.cmd("adb", ["devices"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.drop(1)
        |> Enum.filter(&String.contains?(&1, "\tdevice"))
        |> Enum.map(&(&1 |> String.split("\t") |> hd() |> String.trim()))
        |> List.first()

      _ ->
        nil
    end
  end
end
