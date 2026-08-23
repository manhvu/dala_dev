defmodule Mix.Tasks.Dala.Location do
  use Mix.Task

  @shortdoc "Spoof the device location (emulator / simulator)"

  @moduledoc """
  Pins a device's location for testing `Dala.Platform.Location` without
  moving.

      mix dala.location set 21.0278,105.8342
      mix dala.location set 37.7749,-122.4194 --device 5554
      mix dala.location reset                     # stop spoofing (iOS Simulator)

  Supported on Android **emulators** (`adb emu geo fix`) and iOS Simulators
  (`xcrun simctl location`). Physical devices need platform tooling — a mock
  location app on Android, Xcode's Features → Location on iOS.
  """

  @switches [device: :string, quiet: :boolean, json: :boolean]

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    {opts, positional, _} = OptionParser.parse(args, switches: @switches)

    DalaDev.Output.configure(quiet: opts[:quiet], json: opts[:json])

    case positional do
      ["set", coords] ->
        case DalaDev.LocationSpoof.parse_coords(coords) do
          {:ok, lat, lng} ->
            handle_result(DalaDev.LocationSpoof.set(lat, lng, opts[:device]))

          {:error, reason} ->
            DalaDev.Output.error(reason)
        end

      ["reset"] ->
        handle_result(DalaDev.LocationSpoof.clear(opts[:device]))

      _ ->
        Mix.raise("Usage: mix dala.location <set <lat>,<lng> | reset> [--device <id>]")
    end
  end

  defp handle_result({:ok, msg}), do: DalaDev.Output.success(msg)
  defp handle_result({:error, reason}) do
    DalaDev.Output.error(reason)
    DalaDev.Output.hint("Run `mix dala.devices` to check what kind of device is connected")
  end
end
