defmodule DalaDev.Output do
  @moduledoc """
  Centralized output helpers for all dala_dev tasks and modules.

  All user-facing output should go through this module instead of raw
  `IO.puts`/`Mix.shell().info` so that:

  - ANSI styling is consistent (and disabled automatically when not a TTY)
  - `--quiet` suppresses non-essential output
  - `--json` machine-readable output is possible for scripting/agents

  Semantic helpers:

      DalaDev.Output.step("Deploying", "Pixel 8")
      DalaDev.Output.success("pushed 42 BEAMs")
      DalaDev.Output.warn("OTP cache is stale")
      DalaDev.Output.error("adb not found")
      DalaDev.Output.hint("Run `mix dala.doctor` to diagnose")

  Timing helper for long operations:

      DalaDev.Output.timed("Deployed to Pixel 8", fn ->
        Deployer.deploy_all()
      end)
  """

  @type level :: :debug | :info | :success | :warn | :error | :hint

  @doc """
  Configures output mode. Called once at the top of each Mix task.

  ## Options

    * `:quiet` — when true, only errors are printed
    * `:json` — when true, structured results should be emitted as JSON
      (tasks opt in individually; see `json?/0`)
  """
  @spec configure(keyword()) :: :ok
  def configure(opts \\ []) do
    Application.put_env(:dala_dev, :output_quiet, !!opts[:quiet])
    Application.put_env(:dala_dev, :output_json, !!opts[:json])
    :ok
  end

  @doc "Returns true if `--quiet` was set via `configure/1`."
  @spec quiet?() :: boolean()
  def quiet?, do: Application.get_env(:dala_dev, :output_quiet, false)

  @doc "Returns true if `--json` was set via `configure/1`."
  @spec json?() :: boolean()
  def json?, do: Application.get_env(:dala_dev, :output_json, false)

  @doc "Prints a step header, e.g. `==> Deploying to devices`."
  @spec step(String.t(), String.t() | nil) :: :ok
  def step(label, detail \\ nil) do
    unless quiet?() do
      text = if detail, do: "#{label} #{detail}", else: label

      puts("#{ansi(:cyan)}==>#{ansi(:reset)} #{text}")
    end

    :ok
  end

  @doc "Info line (suppressed in quiet mode)."
  @spec info(String.t()) :: :ok | nil
  def info(message), do: emit(:info, message)

  @spec success(String.t()) :: :ok | nil
  def success(message), do: emit(:success, message)

  @spec warn(String.t()) :: :ok | nil
  def warn(message), do: emit(:warn, message)

  @spec error(String.t()) :: :ok | nil
  def error(message), do: emit(:error, message)

  @spec hint(String.t()) :: :ok | nil
  def hint(message), do: emit(:hint, message)

  @doc false
  @spec emit(level(), String.t()) :: :ok | nil
  defp emit(:info, msg), do: unless(quiet?(), do: plain(msg))

  defp emit(:success, msg),
    do: unless(quiet?(), do: puts(" #{ansi(:green)}✓#{ansi(:reset)} #{msg}"))

  defp emit(:warn, msg), do: puts(" #{ansi(:yellow)}!#{ansi(:reset)} #{msg}")
  defp emit(:error, msg), do: puts(" #{ansi(:red)}✗#{ansi(:reset)} #{msg}")

  defp emit(:hint, msg),
    do: puts("   #{ansi(:faint)}→#{ansi(:reset)} #{msg}")

  @doc """
  Runs `fun`, printing `<label>... done (1.2s)` on success or
  `<label>... failed (3.4s)` on raise. Returns the fun's result.
  """
  @spec timed(String.t(), (-> term())) :: term()
  def timed(label, fun) do
    {elapsed, result} =
      :timer.tc(fn ->
        try do
          {:ok, fun.()}
        rescue
          e -> {:raise, e, __STACKTRACE__}
        end
      end)

    case result do
      {:ok, value} ->
        unless quiet?(), do: puts("#{label} (#{format_elapsed(elapsed)})")
        value

      {:raise, exception, stacktrace} ->
        unless quiet?(), do: puts("#{label} failed (#{format_elapsed(elapsed)})")

        reraise exception, stacktrace
    end
  end

  @doc """
  Formats elapsed time from `:timer.tc` microseconds as a human string.
  Public for testing.
  """
  @spec format_elapsed(non_neg_integer()) :: String.t()
  def format_elapsed(microseconds) when microseconds < 1_000 do
    "#{microseconds}µs"
  end

  @spec format_elapsed(non_neg_integer()) :: String.t()
  def format_elapsed(microseconds) when microseconds < 1_000_000 do
    "#{Float.round(microseconds / 1_000, 1)}ms"
  end

  @spec format_elapsed(non_neg_integer()) :: String.t()
  def format_elapsed(microseconds) do
    seconds = microseconds / 1_000_000

    if seconds < 60 do
      "#{Float.round(seconds, 1)}s"
    else
      minutes = div(trunc(seconds), 60)
      remaining = Float.round(seconds - minutes * 60, 0)
      "#{minutes}m#{trunc(remaining)}s"
    end
  end

  @doc "Formats a byte count as a human-readable string."
  @spec format_bytes(non_neg_integer()) :: String.t()
  def format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  # ── Internals ────────────────────────────────────────────────────────────────

  defp plain(msg), do: Mix.shell().info(msg)

  defp puts(msg) do
    # Strip ANSI when not writing to a TTY so piped/redirected output stays clean.
    if IO.ANSI.enabled?() do
      Mix.shell().info(msg)
    else
      ansi_escape = Regex.compile!("\e\\[[0-9;]*m")
      Mix.shell().info(Regex.replace(ansi_escape, msg, ""))
    end
  end

  defp ansi(name) do
    if IO.ANSI.enabled?(), do: apply(IO.ANSI, name, []), else: ""
  end
end
