defmodule DalaDev.Utils do
  @moduledoc """
  Shared utility functions used across the dala_dev codebase.

  This module centralizes common operations to reduce duplication
  and ensure consistent behavior across modules.
  """

  @doc """
  Compiles a regex pattern with the given options.

  Centralizes regex compilation to avoid duplicating `Regex.compile!/2` calls
  and provides a single place to handle compilation errors.

  ## Examples

      iex> DalaDev.Utils.compile_regex("hello\\s+world")
      ~r/hello\\s+world/

  """
  @spec compile_regex(String.t(), String.t()) :: Regex.t()
  def compile_regex(pattern, opts \\ "") do
    case Regex.compile(pattern, opts) do
      {:ok, regex} ->
        regex

      {:error, {reason, position}} ->
        raise "Invalid regex pattern: #{inspect(pattern)}, " <>
                "error: #{reason} at position #{position}"
    end
  end

  @doc """
  Normalizes CLI arguments so underscored long flags keep working.

  OptionParser only recognizes hyphenated long options (`--dry-run`);
  passing the documented `--dry_run` spelling is silently dropped on
  current Elixir releases. Rewrites every argv token that looks like a
  flag (starts with `--`, including `--flag=value` form) so both
  spellings parse identically. Non-flag values are passed through.

  ## Examples

      iex> DalaDev.Utils.normalize_cli_args(["a.txt", "--on_conflict", "skip"])
      ["a.txt", "--on-conflict", "skip"]

      iex> DalaDev.Utils.normalize_cli_args(["--dry_run=true"])
      ["--dry-run=true"]

  """
  @spec normalize_cli_args([String.t()]) :: [String.t()]
  def normalize_cli_args(args) when is_list(args) do
    Enum.map(args, fn
      "--" <> flag ->
        case String.split(flag, "=", parts: 2) do
          [name, value] -> "--" <> String.replace(name, "_", "-") <> "=" <> value
          [name] -> "--" <> String.replace(name, "_", "-")
        end

      other ->
        other
    end)
  end

  @doc """
  Safely runs ADB with timeout protection.

  Runs `adb` directly (no shell involved), and kills the process if it exceeds
  the timeout. Works identically on macOS, Linux, and Windows — no external
  `timeout` binary required.

  Returns `{:ok, output}` on success, `{:error, reason}` on failure where
  `reason` is trimmed output text or `:timeout`.

  ## Options

  - `:timeout` - timeout in milliseconds (default: 8000)
  - `:stderr_to_stdout` - whether to merge stderr (default: true)
  - `:exec` - optional 2-arity fun `(args, opts) :: {output, exit_code}`
    overriding execution (test seam)
  """
  @spec run_adb_with_timeout(list(String.t()), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run_adb_with_timeout(args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 8000)
    exec = Keyword.get(opts, :exec, &exec_adb/2)

    task = Task.async(fn -> exec.(args, Keyword.take(opts, [:stderr_to_stdout])) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} -> {:ok, String.trim(output)}
      {:ok, {output, _exit_code}} -> {:error, String.trim(output)}
      {:exit, reason} -> {:error, "adb crashed: #{inspect(reason)}"}
      nil -> {:error, :timeout}
    end
  end

  defp exec_adb(args, opts) do
    System.cmd("adb", args, stderr_to_stdout: Keyword.get(opts, :stderr_to_stdout, true))
  rescue
    e -> {Exception.message(e), 127}
  end

  @doc """
  Runs an ADB command for a specific device with timeout.

  Convenience wrapper that prepends `-s <serial>` to the arguments.
  """
  @spec run_adb_for_device(String.t(), list(String.t()), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def run_adb_for_device(serial, args, opts \\ []) do
    run_adb_with_timeout(["-s", serial | args], opts)
  end

  @doc """
  Checks if ADB is available in the system PATH.
  """
  @spec adb_available?() :: boolean()
  def adb_available? do
    command_available?("adb")
  end

  @doc """
  Parses ADB devices output into a list of device identifiers.

  Expects output from `adb devices` command.
  """
  @spec parse_adb_devices_output(String.t()) :: [String.t()]
  def parse_adb_devices_output(output) do
    output
    |> String.split("\n")
    |> Enum.drop(1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.map(&String.split(&1, "\t"))
    |> Enum.map(&List.first/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Checks if a command is available in the system PATH.
  """
  @spec command_available?(String.t()) :: boolean()
  def command_available?(cmd) do
    System.find_executable(cmd) != nil
  end

  @doc """
  Ensures a directory exists, creating it if necessary.

  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec ensure_dir(String.t()) :: :ok | {:error, term()}
  def ensure_dir(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, _} = err -> err
    end
  end

  @doc """
  Formats a byte size into a human-readable string.
  """
  @spec format_bytes(non_neg_integer()) :: String.t()
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  def format_bytes(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  def format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
end
