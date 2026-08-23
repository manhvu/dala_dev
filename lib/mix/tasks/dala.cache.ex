defmodule Mix.Tasks.Dala.Cache do
  use Mix.Task

  @shortdoc "Show or clear the machine-wide caches Dala writes to"

  @moduledoc """
  Inspects every cache `mix dala.*` writes to outside the project tree, and
  (with `--clear`) deletes them. Distinct from `mix clean` (build artifacts
  in `_build/`) and `mix deps.clean` (deps in `deps/`) — this targets caches
  in your home directory that survive across projects.

  By default the command is read-only — it prints a summary of what's on
  disk and exits. Pass `--clear` to wipe Dala's own cache, and add
  `--include-transitive` to also wipe caches owned by transitive deps
  (currently `elixir_make`, used by `exqlite` for its prebuilt NIF tarball).

  Caches we *do not* touch — even with `--include-transitive` — because
  they're shared with the rest of your Elixir/Android/iOS work:

    * `~/.hex/`, `~/.mix/`           — Hex/Mix global state
    * `~/.gradle/`                   — Gradle wrapper + caches
    * `~/Library/Developer/Xcode/`   — Xcode DerivedData, Index
    * `~/Library/Caches/com.apple.dt.*` — Xcode-related caches

  Clean those manually if you want a true scorched-earth reset.

  ## Usage

      mix dala.cache                                 # show what's on disk (default)
      mix dala.cache --include-transitive            # also list elixir_make cache
      mix dala.cache --clear                         # delete Dala's own cache
      mix dala.cache --clear --include-transitive    # delete Dala's + elixir_make's
      mix dala.cache --clear --yes                   # skip the confirmation prompt
      mix dala.cache --dry-run                       # explicit "list only" (alias for default)

  ## Where the caches live

  **Dala's own cache** — pre-built OTP runtimes (iOS sim, iOS device, Android
  arm64, Android arm32). One per platform/ABI; ~200–400 MB each. Reused
  across every Dala project on this machine.

      $DALA_CACHE_DIR     (if set)
      ~/.dala/cache/      (default)

  Override with `DALA_CACHE_DIR` in your shell or `dala.exs` if you want it
  somewhere project-local or sandbox-friendly (Nix users: this is the
  switch you want).

  **`elixir_make` cache** — pre-built NIF tarballs that `exqlite` and other
  NIF-using deps download instead of recompiling from source. The same
  tarball is reused across every Elixir project on this machine.

      ~/Library/Caches/elixir_make/    (macOS)
      ~/.cache/elixir_make/            (Linux)

  This belongs to `elixir_make`, not Dala — but `mix dala.deploy` is what
  populated it, so we offer to clear it here.
  """

  @switches [
    clear: :boolean,
    include_transitive: :boolean,
    dry_run: :boolean,
    yes: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    targets = resolve_targets(opts)

    print_header()
    print_targets(targets)

    cond do
      opts[:clear] != true ->
        DalaDev.Output.info("")
        DalaDev.Output.hint("(read-only — pass --clear to delete; add --include-transitive to widen)")

      opts[:dry_run] == true ->
        DalaDev.Output.info("")
        DalaDev.Output.info("(--dry-run: nothing was deleted)")

      opts[:yes] == true or confirm_delete?(targets) ->
        delete_targets(targets)

      true ->
        DalaDev.Output.info("")
        DalaDev.Output.warn("Aborted.")
    end
  end

  # ── Target resolution ──────────────────────────────────────────────────────

  defp resolve_targets(opts) do
    list = [our_cache()] ++ sim_runtime_targets()
    list = if opts[:include_transitive], do: list ++ [elixir_make_cache()], else: list
    list
  end

  @doc false
  @spec our_cache() :: %{name: String.t(), path: String.t(), kind: :ours}
  def our_cache do
    base =
      System.get_env("DALA_CACHE_DIR") ||
        Path.join([System.user_home!(), ".dala", "cache"])

    %{
      name: "Dala OTP runtime cache",
      path: base,
      kind: :ours,
      hint: "set DALA_CACHE_DIR to relocate; otherwise lives at ~/.dala/cache"
    }
  end

  # Return both the new (~/.dala/runtime/ios-sim) and legacy (/tmp/otp-ios-sim)
  # iOS simulator runtime locations, plus any DALA_SIM_RUNTIME_DIR override —
  # deduplicated. Users can have stale data in either place if they've used
  # multiple projects, so list both unconditionally regardless of which one
  # the current project would resolve to.
  @doc false
  @spec sim_runtime_targets() :: [map()]
  def sim_runtime_targets do
    new_default = DalaDev.Paths.default_runtime_dir()
    legacy = DalaDev.Paths.legacy_tmp_path()
    override = System.get_env("DALA_SIM_RUNTIME_DIR")

    [new_default, legacy, override]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(&sim_runtime_entry/1)
  end

  defp sim_runtime_entry(path) do
    %{
      name: "iOS simulator runtime (#{label_for_runtime(path)})",
      path: path,
      kind: :ours,
      hint: hint_for_runtime(path)
    }
  end

  defp label_for_runtime(path) do
    cond do
      path == DalaDev.Paths.default_runtime_dir() -> "current default"
      path == DalaDev.Paths.legacy_tmp_path() -> "legacy /tmp location"
      true -> "DALA_SIM_RUNTIME_DIR override"
    end
  end

  defp hint_for_runtime(path) do
    cond do
      path == DalaDev.Paths.default_runtime_dir() ->
        "writable OTP root for new projects; dala_new ≥ 0.1.20"

      path == DalaDev.Paths.legacy_tmp_path() ->
        "used by projects whose ios/build.sh predates DALA_SIM_RUNTIME_DIR"

      true ->
        "set MOB_SIM_RUNTIME_DIR to override the default"
    end
  end

  @doc false
  @spec elixir_make_cache() :: %{name: String.t(), path: String.t(), kind: :transitive}
  def elixir_make_cache do
    %{
      name: "elixir_make precompiled-NIF cache",
      path: elixir_make_cache_path(),
      kind: :transitive,
      hint: "owned by elixir_make (used by exqlite); reused across all Elixir projects"
    }
  end

  @doc false
  @spec elixir_make_cache_path() :: String.t()
  def elixir_make_cache_path do
    case :os.type() do
      {:unix, :darwin} ->
        Path.join([System.user_home!(), "Library", "Caches", "elixir_make"])

      _ ->
        Path.join([System.user_home!(), ".cache", "elixir_make"])
    end
  end

  # ── Reporting ──────────────────────────────────────────────────────────────

  defp print_header do
    DalaDev.Output.info("")
    DalaDev.Output.step("Dala caches on this machine")
    DalaDev.Output.info("")
  end

  defp print_targets(targets) do
    Enum.each(targets, fn t ->
      {exists?, size_str} = path_status(t.path)

      status_icon =
        case {exists?, t.kind} do
          {true, :ours} -> "●"
          {true, :transitive} -> "●"
          {false, _} -> "○"
        end

      DalaDev.Output.info("  #{status_icon} #{t.name}")
      DalaDev.Output.info("path: #{t.path}")
      DalaDev.Output.info("size: #{size_str}")
      DalaDev.Output.info("note: #{t.hint}")
      DalaDev.Output.info("")
    end)
  end

  @doc false
  @spec path_status(String.t()) :: {boolean(), String.t()}
  def path_status(path) do
    cond do
      not File.exists?(path) ->
        {false, "(not present)"}

      File.dir?(path) ->
        {true, format_size(dir_size(path))}

      true ->
        case File.stat(path) do
          {:ok, %File.Stat{size: s}} -> {true, format_size(s)}
          _ -> {true, "(unknown)"}
        end
    end
  end

  defp dir_size(dir) do
    Path.wildcard(Path.join(dir, "**/*"), match_dot: true)
    |> Enum.reduce(0, fn p, acc ->
      case File.stat(p) do
        {:ok, %File.Stat{type: :regular, size: s}} -> acc + s
        _ -> acc
      end
    end)
  end

  @doc false
  @spec format_size(non_neg_integer()) :: String.t()
  def format_size(bytes) when bytes < 1024, do: "#{bytes} B"

  def format_size(bytes) when bytes < 1024 * 1024 do
    :io_lib.format("~.1f KB", [bytes / 1024]) |> IO.iodata_to_binary()
  end

  def format_size(bytes) when bytes < 1024 * 1024 * 1024 do
    :io_lib.format("~.1f MB", [bytes / (1024 * 1024)]) |> IO.iodata_to_binary()
  end

  def format_size(bytes) do
    :io_lib.format("~.2f GB", [bytes / (1024 * 1024 * 1024)]) |> IO.iodata_to_binary()
  end

  # ── Deletion ───────────────────────────────────────────────────────────────

  defp confirm_delete?(targets) do
    paths_to_delete = Enum.filter(targets, &File.exists?(&1.path))

    if paths_to_delete == [] do
      DalaDev.Output.info("Nothing to delete — all listed caches are already absent.")
      false
    else
      DalaDev.Output.info("")
      IO.write("Delete the paths above? [y/N] ")

      case IO.gets("") do
        :eof -> false
        input -> String.trim(input) |> String.downcase() == "y"
      end
    end
  end

  defp delete_targets(targets) do
    Enum.each(targets, fn t ->
      if File.exists?(t.path) do
        case File.rm_rf(t.path) do
          {:ok, _} ->
            DalaDev.Output.success("deleted #{t.path}")

          {:error, reason, file} ->
            DalaDev.Output.error(
              "failed #{t.path} — #{inspect(reason)} (#{file})"
            )
        end
      end
    end)

    DalaDev.Output.info("")
  end
end
