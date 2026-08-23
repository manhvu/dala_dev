defmodule Mix.Tasks.Dala.Emulators do
  use Mix.Task

  @shortdoc "List, start, and stop Android emulators / iOS simulators"

  @moduledoc """
  Manage virtual devices: Android emulators (AVDs) and iOS simulators.

  ## Examples

      mix dala.emulators                        # list all (default)
      mix dala.emulators --list                 # same as above
      mix dala.emulators --list --android       # Android only
      mix dala.emulators --list --ios           # iOS only

      mix dala.emulators --start --id Pixel_8_API_34
      mix dala.emulators --start --id 78354490
      mix dala.emulators --start --id Pixel_8_API_34 --recipe selinux-off
      mix dala.emulators --start --id Pixel_8_API_34 --emulator_args "-no-audio -gpu host"

      mix dala.emulators --stop --id emulator-5554
      mix dala.emulators --stop --id 78354490
      mix dala.emulators --stop --all           # everything booted

  `--id` accepts the same display IDs `mix dala.devices` shows, plus AVD
  names. For Android the running serial (`emulator-5554`) also works.

  ## Launch recipes (Android)

    * `selinux-off` — boot with SELinux disabled; workaround for the Android
      17 preview where BEAM startup dies on cgroup SELinux denials.
      Dev-only, never on real hardware.
    * `cold-boot` — skip quick-boot state (`-no-snapshot`)
    * `wipe-data` — start with wiped userdata (`-wipe-data`, destructive)
    * `no-audio` — `-no-audio`
    * `gpu-host` — use host GPU (`-gpu host`)

  Free-form extra flags: `--emulator_args "-flag value ..."`.
  Recipes and flags combine when both are given.

  Out of scope: creating new AVDs or installing simulator runtimes — those
  involve license acceptance and multi-GB downloads. Use Android Studio /
  Xcode for that.
  """

  alias DalaDev.{Device, Emulators}

  @switches [
    list: :boolean,
    start: :boolean,
    stop: :boolean,
    android: :boolean,
    ios: :boolean,
    id: :string,
    all: :boolean,
    recipe: :string,
    emulator_args: :string
  ]

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    cond do
      opts[:start] -> do_start(opts)
      opts[:stop] -> do_stop(opts)
      true -> do_list(opts)
    end
  end

  # ── List ──────────────────────────────────────────────────────────────────

  defp do_list(opts) do
    # Both shown if neither flag specified, otherwise only the requested one(s).
    android? = Keyword.get(opts, :android, false)
    ios? = Keyword.get(opts, :ios, false)
    show_android = android? or (not android? and not ios?)
    show_ios = ios? or (not android? and not ios?)

    DalaDev.Output.info("")

    if show_android do
      print_android_section()
      DalaDev.Output.info("")
    end

    if show_ios do
      print_ios_section()
      DalaDev.Output.info("")
    end
  end

  defp print_android_section do
    DalaDev.Output.step("Android emulators (AVDs)")

    case Emulators.list_android() do
      {:ok, []} ->
        DalaDev.Output.info("  (no AVDs configured — create one in Android Studio)")

      {:ok, avds} ->
        Enum.each(avds, &print_avd/1)

      {:error, reason} ->
        DalaDev.Output.warn("#{reason}")
    end
  end

  defp print_ios_section do
    DalaDev.Output.step("iOS simulators")

    case Emulators.list_ios() do
      {:ok, sims} ->
        # Group by runtime and sort booted-first within each group.
        sims
        |> Enum.sort_by(&{&1.runtime, not &1.running, &1.name})
        |> Enum.each(&print_sim/1)

      {:error, reason} ->
        DalaDev.Output.warn("#{reason}")
    end
  end

  defp print_avd(%Emulators{platform: :android} = a) do
    dot = if a.running, do: "●", else: "○"
    suffix = if a.running, do: " (running, #{a.serial})", else: ""
    DalaDev.Output.info("  #{dot}  #{a.name}#{suffix}")
  end

  defp print_sim(%Emulators{platform: :ios} = s) do
    dot = if s.running, do: "●", else: "○"
    state = if s.running, do: "booted, ", else: ""
    short_id = String.replace(s.id, "-", "") |> String.slice(0, 8) |> String.downcase()

    DalaDev.Output.info("  #{dot}  #{pad(s.name, 28)} #{s.runtime}  (#{state}#{short_id})")
  end

  # ── Start ─────────────────────────────────────────────────────────────────

  defp do_start(opts) do
    id = opts[:id]

    if is_nil(id) do
      Mix.raise("--start requires --id <id>. See `mix dala.emulators --list` for IDs.")
    end

    case extra_args(opts) do
      {:ok, extra} ->
        start_resolved(resolve(id), opts, extra)

      :error ->
        Mix.raise(
          "Unknown recipe #{inspect(opts[:recipe])}. " <>
            "Available: #{Enum.join(Emulators.recipes(), ", ")}"
        )
    end
  end

  # Resolve --recipe / --emulator-args into raw Android emulator CLI flags.
  # Recipes are curated presets (see DalaDev.Emulators.recipes/0); free-form
  # flags pass through as-is. Both combine when given together.
  defp extra_args(opts) do
    from_recipe =
      case opts[:recipe] do
        nil -> {:ok, []}
        name -> Emulators.recipe_args(name)
      end

    from_cli =
      case opts[:emulator_args] do
        nil -> {:ok, []}
        raw when is_binary(raw) -> {:ok, split_flags(raw)}
        _ -> {:ok, []}
      end

    with {:ok, recipe} <- from_recipe,
         {:ok, cli} <- from_cli do
      {:ok, recipe ++ cli}
    end
  end

  # Split a flag string on whitespace, keeping double-quoted runs together
  # and then stripping their quotes. Pure — public for testing.
  @doc false
  @spec split_flags(String.t()) :: [String.t()]
  def split_flags(raw) do
    raw
    |> String.split(DalaDev.Utils.compile_regex("\"[^\"]*\"|\\S+"), include_captures: true)
    |> Enum.map(&(String.trim(&1) |> String.trim("\"")))
    |> Enum.reject(&(&1 == ""))
  end

  defp start_resolved({:android, %Emulators{name: avd_name, running: false}}, _opts, extra) do
    DalaDev.Output.step("Starting Android emulator: #{avd_name}" <> describe_extra(extra))

    case Emulators.start_android(avd_name, extra) do
      :ok ->
        DalaDev.Output.success(
          "Started. (boots in background — `adb wait-for-device` to block)"
        )

      {:error, reason} ->
        Mix.raise(reason)
    end
  end

  defp start_resolved({:android, %Emulators{name: avd_name, running: true, serial: serial}}, _opts, _extra) do
    DalaDev.Output.info("Already running: #{avd_name} (#{serial})")
  end

  defp start_resolved({:ios, %Emulators{name: name, id: udid, running: false}}, _opts, extra) do
    unless extra == [] do
      DalaDev.Output.warn(
        "Recipes/emulator-flags apply to Android only; ignoring for iOS simulator."
      )
    end

    DalaDev.Output.step("Booting iOS simulator: #{name}")

    case Emulators.start_ios(udid) do
      :ok -> DalaDev.Output.success("Booted.")
      {:error, reason} -> Mix.raise(reason)
    end
  end

  defp start_resolved({:ios, %Emulators{name: name, running: true}}, _opts, _extra) do
    DalaDev.Output.info("Already booted: #{name}")
  end

  defp start_resolved(:not_found, opts, _extra) do
    Mix.raise("No emulator/simulator matched #{inspect(opts[:id])}. Run `mix dala.emulators --list`.")
  end

  defp describe_extra([]), do: ""

  defp describe_extra(extra), do: " (#{Enum.join(extra, " ")})"

  # ── Stop ──────────────────────────────────────────────────────────────────

  defp do_stop(opts) do
    cond do
      opts[:all] ->
        do_stop_all(opts)

      opts[:id] ->
        do_stop_one(opts[:id])

      true ->
        Mix.raise(
          "--stop needs either --id <id> or --all. " <>
            "Use --all to stop every running emulator/simulator."
        )
    end
  end

  defp do_stop_one(id) do
    case resolve(id) do
      {:android, %Emulators{running: true, serial: serial, name: name}} ->
        DalaDev.Output.step("Stopping Android emulator: #{name} (#{serial})")

        case Emulators.stop_android(serial) do
          :ok -> DalaDev.Output.success("Stopped.")
          {:error, reason} -> Mix.raise(reason)
        end

      {:android, %Emulators{running: false, name: name}} ->
        DalaDev.Output.info("Not running: #{name}")

      {:ios, %Emulators{running: true, id: udid, name: name}} ->
        DalaDev.Output.step("Shutting down iOS simulator: #{name}")

        case Emulators.stop_ios(udid) do
          :ok -> DalaDev.Output.success("Stopped.")
          {:error, reason} -> Mix.raise(reason)
        end

      {:ios, %Emulators{running: false, name: name}} ->
        DalaDev.Output.info("Not booted: #{name}")

      :not_found ->
        Mix.raise(
          "No emulator/simulator matched #{inspect(id)}. Run `mix dala.emulators --list`."
        )
    end
  end

  defp do_stop_all(opts) do
    # Both shown if neither flag specified, otherwise only the requested one(s).
    android? = Keyword.get(opts, :android, false)
    ios? = Keyword.get(opts, :ios, false)
    show_android = android? or (not android? and not ios?)
    show_ios = ios? or (not android? and not ios?)

    running =
      []
      |> then(fn acc ->
        if show_android do
          case Emulators.list_android() do
            {:ok, avds} -> acc ++ Enum.filter(avds, & &1.running)
            _ -> acc
          end
        else
          acc
        end
      end)
      |> then(fn acc ->
        if show_ios do
          case Emulators.list_ios() do
            {:ok, sims} -> acc ++ Enum.filter(sims, & &1.running)
            _ -> acc
          end
        else
          acc
        end
      end)

    if running == [] do
      DalaDev.Output.info("No running emulators or simulators.")
    else
      names = Enum.map_join(running, ", ", & &1.name)
      DalaDev.Output.step("Stopping #{length(running)} running: #{names}")

      Enum.each(running, fn
        %Emulators{platform: :android, serial: serial, name: name} ->
          case Emulators.stop_android(serial) do
            :ok -> DalaDev.Output.success(name)
            {:error, reason} -> DalaDev.Output.error("#{name}: #{reason}")
          end

        %Emulators{platform: :ios, id: udid, name: name} ->
          case Emulators.stop_ios(udid) do
            :ok -> DalaDev.Output.success(name)
            {:error, reason} -> DalaDev.Output.error("#{name}: #{reason}")
          end
      end)
    end
  end

  # ── Resolution ────────────────────────────────────────────────────────────

  # Try Android first then iOS — they don't share id formats so collisions
  # are vanishingly rare. Match against the AVD name (Android), the running
  # adb serial (Android), the UDID (iOS), or the 8-char display id (iOS).
  defp resolve(id) do
    android_match =
      case Emulators.list_android() do
        {:ok, avds} -> Enum.find(avds, &android_id_match?(&1, id))
        _ -> nil
      end

    if android_match do
      {:android, android_match}
    else
      case Emulators.list_ios() do
        {:ok, sims} ->
          case Enum.find(sims, &ios_id_match?(&1, id)) do
            nil -> :not_found
            sim -> {:ios, sim}
          end

        _ ->
          :not_found
      end
    end
  end

  defp android_id_match?(%Emulators{name: name, serial: serial}, id) do
    String.downcase(name) == String.downcase(id) or
      (serial != nil and String.downcase(serial) == String.downcase(id))
  end

  defp ios_id_match?(%Emulators{id: udid}, id) do
    # Build a fake Device just to reuse Device.match_id?/2's "display_id or serial"
    # logic. Simulator display_id = first 8 hex chars of UDID with dashes removed.
    fake = %Device{platform: :ios, type: :simulator, serial: udid}
    Device.match_id?(fake, id)
  end


  defp pad(s, n) do
    pad_len = max(n - String.length(s), 0)
    s <> String.duplicate(" ", pad_len)
  end
end
