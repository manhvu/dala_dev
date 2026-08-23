defmodule Mix.Tasks.Dala.Clipboard do
  use Mix.Task

  @shortdoc "Read or set the device clipboard (iOS Simulator)"

  @moduledoc """
  Paste long strings into device text fields without typing them on the
  virtual keyboard.

      mix dala.clipboard get                     # print clipboard contents
      mix dala.clipboard set "some long token"   # replace clipboard contents
      mix dala.clipboard get --device 78354490

  Supported on iOS Simulators (`xcrun simctl pbpaste/pbcopy`). Android blocks
  background clipboard access, so use `adb shell input text "..."` with the
  field focused instead.
  """

  @switches [device: :string, quiet: :boolean, json: :boolean]

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    {opts, positional, _} = OptionParser.parse(args, switches: @switches)

    DalaDev.Output.configure(quiet: opts[:quiet], json: opts[:json])

    case positional do
      ["get"] ->
        handle_result(DalaDev.DeviceClipboard.get(opts[:device]))

      ["set", text] ->
        handle_result(DalaDev.DeviceClipboard.put(text, opts[:device]))

      _ ->
        Mix.raise("Usage: mix dala.clipboard <get | set \"text\"> [--device <id>]")
    end
  end

  defp handle_result({:ok, msg}) do
    unless DalaDev.Output.quiet?(), do: Mix.shell().info(msg)
  end

  defp handle_result({:error, reason}) do
    DalaDev.Output.error(reason)
  end
end
