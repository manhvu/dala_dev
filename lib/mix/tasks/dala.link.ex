defmodule Mix.Tasks.Dala.Link do
  use Mix.Task

  @shortdoc "Open a URL / deep link on connected devices"

  @moduledoc """
  Fires a URL or deep link at your device screens — the dev-machine side of
  `Dala.Platform.Linking`.

      mix dala.link https://example.com
      mix dala.link myapp://product/42
      mix dala.link myapp://product/42 --device 78354490

  Android uses `am start -a android.intent.action.VIEW -d <url>`;
  iOS Simulator uses `xcrun simctl openurl`.
  """

  @switches [device: :string, quiet: :boolean, json: :boolean]

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    {opts, positional, _} = OptionParser.parse(args, switches: @switches)

    DalaDev.Output.configure(quiet: opts[:quiet], json: opts[:json])

    case positional do
      [url] ->
        unless DalaDev.DeepLink.valid_url?(url) do
          DalaDev.Output.error(
            "#{inspect(url)} has no URL scheme — expected something like https://… or myapp://…"
          )

          exit({:shutdown, 1})
        end

        results = DalaDev.DeepLink.open(url, device: opts[:device])

        report(results)

      _ ->
        Mix.raise("Usage: mix dala.link <url> [--device <id>]")
    end
  end

  # Prints per-device outcomes. Public test seam — takes prebuilt results.
  @doc false
  @spec report([{String.t(), term()}]) :: :ok
  def report([]) do
    DalaDev.Output.warn("No devices found.")
    :ok
  end

  def report(results) do
    Enum.each(results, fn
      {label, {:ok, msg}} -> DalaDev.Output.success("#{label}: #{msg}")
      {label, {:error, reason}} -> DalaDev.Output.error("#{label}: #{reason}")
    end)

    :ok
  end
end
