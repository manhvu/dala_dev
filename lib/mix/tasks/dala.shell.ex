defmodule Mix.Tasks.Dala.Shell do
  use Mix.Task

  @shortdoc "Shell into the app sandbox on a connected device"

  @moduledoc """
  Drops you into (or runs commands inside) your app's private data directory.

      mix dala.shell                          # print the command for your shell
      mix dala.shell --exec "ls -la"          # run one command inside it
      mix dala.shell --exec "cat files/prefs.txt" --device 5554
      mix dala.shell --bundle com.example.myapp

  ## Platform behaviour

    * Android → `adb -s <serial> shell run-as <bundle>` — an interactive shell
      rooted at `/data/data/<bundle>`. `--exec` runs one shot via `run-as -c`.
    * iOS Simulator → prints the app's data container path on the host
      (`xcrun simctl get_app_container <udid> <bundle> data`); `--exec` runs a
      shell with the container as working directory.
    * iOS physical → not supported (no public sandbox exec).

  Without `--exec`, the exact command is printed for copy-paste — interactive
  TTY sessions are more reliable from your own terminal than from a Mix task.
  """

  @switches [
    device: :string,
    exec: :string,
    bundle_id: :string,
    quiet: :boolean,
    json: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    DalaDev.Output.configure(quiet: opts[:quiet], json: opts[:json])

    bundle_id = opts[:bundle_id] || DalaDev.Config.bundle_id()

    case DalaDev.DeviceShell.resolve_target(opts[:device]) do
      {:error, reason} ->
        DalaDev.Output.error(reason)
        DalaDev.Output.hint("Run `mix dala.devices` to see what's connected")

      {:ok, target, label} ->
        plan =
          if opts[:exec] do
            DalaDev.DeviceShell.exec_command(target, bundle_id, opts[:exec])
          else
            DalaDev.DeviceShell.open_command(target, bundle_id)
          end

        handle_plan(plan, label, bundle_id, !!opts[:exec])
    end
  end

  @doc false
  @spec handle_plan(DalaDev.DeviceShell.command(), String.t(), String.t(), boolean()) ::
          :ok | nil
  def handle_plan(:unsupported, _label, _bundle, _exec?) do
    DalaDev.Output.error(
      "This device has no CLI-accessible app sandbox (physical iOS)."
    )

    DalaDev.Output.hint("Use Files-app debugging or pull files with `mix dala.pull_file`.")
  end

  @doc false
  def handle_plan({kind, command}, label, bundle_id, exec?) do
    cond do
      exec? ->
        DalaDev.Output.step("Running in #{label} (#{bundle_id})")
        status = DalaDev.DeviceShell.run(command)

        unless status == 0 do
          DalaDev.Output.warn("command exited with status #{status}")
        end

      kind == :dir ->
        DalaDev.Output.step("#{label} app data container:")
        DalaDev.Output.info(command)
        DalaDev.Output.hint("Run it to get the host-side container path.")

      true ->
        DalaDev.Output.step("#{label} app sandbox — run:")
        DalaDev.Output.info(command)
        DalaDev.Output.hint("Or one-shot: mix dala.shell --exec \"<command>\"")
    end
  end
end
