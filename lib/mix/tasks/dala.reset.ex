defmodule Mix.Tasks.Dala.Reset do
  use Mix.Task

  @shortdoc "Force-stop Dala app processes on devices, optionally wipe data"

  @moduledoc """
  Full app reset for connected devices — more thorough than an Activity
  restart. On Android this force-stops **both** the project package and the
  `com.dala.<app>` wrapper that hosts BeamForegroundService (which otherwise
  outlives the Activity and keeps a stale BEAM running), then clears the
  logcat buffer so the next launch's logs start clean.

  ## Usage

      mix dala.reset                     # stop apps on all devices
      mix dala.reset --device 5554       # one device only
      mix dala.reset --data              # also wipe app data
      mix dala.reset --data --device R5CW3089HVB

  ## Notes

    * Android: `am force-stop` both packages + `logcat -c`; with `--data`
      additionally `pm clear` each package.
    * iOS Simulator: `simctl terminate` (+ `simctl uninstall` with `--data`).
    * iOS physical: not supported — stop the app from the device itself.

  After a reset, relaunch with `mix dala.connect` or `mix dala.deploy`.
  """

  @switches [
    device: :string,
    data: :boolean,
    bundle_id: :string,
    quiet: :boolean,
    json: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    DalaDev.Output.configure(quiet: opts[:quiet], json: opts[:json])

    results =
      DalaDev.AppReset.reset_all(
        device: opts[:device],
        clear_data: Keyword.get(opts, :data, false),
        bundle_id: opts[:bundle_id]
      )

    report(results, !!opts[:json])
  end

  # Prints per-device outcomes (and JSON when requested). Public test seam.
  @doc false
  @spec report([{String.t(), term()}], boolean()) :: :ok
  def report(results, json?) do
    if results == [] do
      DalaDev.Output.warn("No devices found.")
      DalaDev.Output.hint("Run `mix dala.devices` to see what's connected")
    else
      Enum.each(results, fn {label, result} ->
        case result do
          {:ok, msg} -> DalaDev.Output.success("#{label}: #{msg}")
          {:error, reason} -> DalaDev.Output.error("#{label}: #{reason}")
        end
      end)
    end

    if json? do
      json =
        JSON.encode!(%{
          results:
            Enum.map(results, fn {label, result} ->
              case result do
                {:ok, msg} -> %{device: label, ok: true, detail: msg}
                {:error, reason} -> %{device: label, ok: false, error: reason}
              end
            end)
        })

      DalaDev.Output.info(json)
    end

    :ok
  end
end
