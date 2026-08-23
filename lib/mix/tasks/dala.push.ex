defmodule Mix.Tasks.Dala.Push do
  use Mix.Task

  @shortdoc "Compile and hot-push changed modules to running dala devices"

  @moduledoc """
  Compiles the project and hot-pushes updated BEAM modules to all running
  Android and iOS devices — no app restart.

  The apps must already be running (start them with `mix dala.connect` or
  `mix dala.deploy` first). Modules are loaded into the live BEAM in place,
  equivalent to calling `nl(Module)` in IEx for each changed module.

  ## Options
    --all        Push all modules, not just those changed since last compile
    --cookie     Erlang cookie (default: dala_secret)
    --device     Target specific device by ID

  ## Examples
      mix dala.push
      mix dala.push --all
      mix dala.push --cookie my_cookie
      mix dala.push --device 5554
      mix dala.push --device R5CW3089HVB
  """

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [all: :boolean, cookie: :string, device: :string],
        aliases: [c: :cookie, d: :device]
      )

    push_all = Keyword.get(opts, :all, false)
    cookie = opts |> Keyword.get(:cookie, "dala_secret") |> String.to_atom()
    device_id = Keyword.get(opts, :device, nil)

    DalaDev.Output.info("")

    snapshot = DalaDev.HotPush.snapshot_beams()
    Mix.Task.run("compile")

    DalaDev.Output.step("Connecting to devices")
    nodes = DalaDev.HotPush.connect(cookie: cookie, device: device_id)

    if nodes == [] do
      DalaDev.Output.warn("No running nodes found.")
      DalaDev.Output.hint("Start apps first: mix dala.connect")
    else
      DalaDev.Output.info("Connected: #{Enum.map_join(nodes, ", ", &to_string/1)}")
      DalaDev.Output.step("Pushing modules")

      {pushed, failed} =
        if push_all,
          do: DalaDev.HotPush.push_all(nodes),
          else: DalaDev.HotPush.push_changed(nodes, snapshot)

      if pushed == 0 and failed == [] do
        DalaDev.Output.warn("Nothing changed.")
      else
        if pushed > 0 do
          DalaDev.Output.success("#{pushed} module(s) pushed")
        end

        Enum.each(failed, fn {mod, reason} ->
          DalaDev.Output.error("#{mod}: #{inspect(reason)}")
        end)
      end
    end
  end
end
