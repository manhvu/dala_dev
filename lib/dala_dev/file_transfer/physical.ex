defmodule DalaDev.FileTransfer.Platform.Physical do
  @moduledoc "iOS Physical device file transfer via xcrun devicectl."

  alias DalaDev.Device

  # ── Push ────────────────────────────────────────────────────────────────────

  @spec push(Device.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def push(%Device{serial: udid}, local, remote, opts) do
    on_conflict = Keyword.get(opts, :on_conflict, :overwrite)
    progress? = Keyword.get(opts, :progress, false)
    bundle = DalaDev.Config.bundle_id()

    if File.exists?(local) do
      staging = Path.join(System.tmp_dir!(), "dala_ios_#{unique()}")
      staging_dir = Path.join(staging, Path.basename(remote))
      File.mkdir_p!(staging_dir)

      try do
        cp_r(local, staging_dir)
        remote_exists? = file_exists?(udid, bundle, remote)

        case {remote_exists?, on_conflict} do
          {true, :skip} ->
            {:ok, "skipped (already exists)"}

          {true, :rename} ->
            renamed = "#{remote}.#{unique()}"
            copy_to_device(udid, bundle, staging_dir, renamed)
            {:ok, "saved as #{Path.basename(renamed)}"}

          _ ->
            copy_to_device(udid, bundle, staging_dir, remote)

            if progress? and File.dir?(local),
              do: {:ok, "pushed (#{length(File.ls!(local))} file(s)) to Documents/#{remote}"},
              else: {:ok, "pushed to Documents/#{remote}"}
        end
      catch
        {:error, reason} -> {:error, reason}
      after
        File.rm_rf!(staging)
      end
    else
      {:error, "local path does not exist: #{local}"}
    end
  end

  # ── Pull ────────────────────────────────────────────────────────────────────

  @spec pull(Device.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def pull(%Device{serial: udid}, remote, local, opts) do
    on_conflict = Keyword.get(opts, :on_conflict, :overwrite)
    bundle = DalaDev.Config.bundle_id()

    case {File.exists?(local), on_conflict} do
      {true, :skip} -> {:ok, "skipped (local file already exists)"}
      {true, :rename} -> pull_from_device(udid, bundle, remote, "#{local}.#{unique()}")
      _ -> pull_from_device(udid, bundle, remote, local)
    end
  end

  # ── Ls ──────────────────────────────────────────────────────────────────────

  @spec ls(Device.t(), String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def ls(%Device{serial: udid}, remote_path) do
    bundle = DalaDev.Config.bundle_id()

    path =
      if remote_path == "" or remote_path == ".",
        do: "Documents",
        else: "Documents/#{remote_path}"

    case run_devicectl(udid, bundle, "info", "files", path) do
      {:ok, out} -> {:ok, parse_file_list(out)}
      {:error, reason} -> {:error, "devicectl ls failed: #{reason}"}
    end
  end

  # ── Sync ────────────────────────────────────────────────────────────────────

  @spec sync(Device.t(), String.t(), String.t(), keyword()) ::
          {:ok, [{:push | :pull | :delete, String.t()}]}
  def sync(%Device{serial: udid}, local, remote, opts) do
    delete? = Keyword.get(opts, :delete, false)
    dry_run? = Keyword.get(opts, :dry_run, false)
    progress? = Keyword.get(opts, :progress, false)
    bundle = DalaDev.Config.bundle_id()
    remote_files = list_remote_dir(udid, bundle, remote)
    local_files = list_files(local)
    local_map = Map.new(local_files, fn {rel, abs} -> {rel, File.stat!(abs)} end)

    remote_map =
      Map.new(remote_files, fn {rel, size, _} -> {rel, {size, :erlang.system_time(:second)}} end)

    actions = compute_sync_actions(local_map, remote_map, delete?)
    if progress? or dry_run?, do: print_actions(actions)
    if dry_run?, do: {:ok, actions}, else: execute_sync(udid, bundle, local, remote, actions)
    {:ok, actions}
  end

  defp execute_sync(_udid, _bundle, _local, remote, actions) do
    Enum.each(actions, fn
      {:push, rel} ->
        DalaDev.Output.warn(
          "    (warning: iOS physical per-file push not yet implemented: #{remote}/#{rel})"
        )

      {:delete, rel} ->
        DalaDev.Output.warn("    (warning: iOS physical delete not supported: #{remote}/#{rel})")

      {:pull, _} ->
        :ok
    end)
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp unique, do: :erlang.unique_integer([:positive])

  defp run_devicectl(udid, bundle, subcmd, action, path) do
    args = [
      "devicectl",
      "device",
      subcmd,
      action,
      "--device",
      udid,
      "--domain-type",
      "appDataContainer",
      "--domain-identifier",
      bundle,
      "--path",
      path
    ]

    case System.cmd("xcrun", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, _} -> {:error, out}
    end
  end

  defp copy_to_device(udid, bundle, local_path, remote_path) do
    args = [
      "devicectl",
      "device",
      "copy",
      "to",
      "--device",
      udid,
      "--domain-type",
      "appDataContainer",
      "--domain-identifier",
      bundle,
      "--source",
      local_path,
      "--destination",
      "Documents/#{remote_path}"
    ]

    case System.cmd("xcrun", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, _} -> throw({:error, "devicectl copy failed: #{out}"})
    end
  end

  defp pull_from_device(udid, bundle, remote, local) do
    staging = Path.join(System.tmp_dir!(), "dala_ios_pull_#{unique()}")
    File.mkdir_p!(staging)

    try do
      args = [
        "devicectl",
        "device",
        "copy",
        "from",
        "--device",
        udid,
        "--domain-type",
        "appDataContainer",
        "--domain-identifier",
        bundle,
        "--source",
        "Documents/#{remote}",
        "--destination",
        staging
      ]

      case System.cmd("xcrun", args, stderr_to_stdout: true) do
        {_, 0} ->
          pulled = Path.join(staging, Path.basename(remote))

          if File.exists?(pulled),
            do:
              (
                File.mkdir_p!(Path.dirname(local))
                File.cp!(pulled, local)
                {:ok, "pulled to #{local}"}
              ),
            else: {:error, "file not found on device: #{remote}"}

        {out, _} ->
          {:error, "devicectl pull failed: #{out}"}
      end
    after
      File.rm_rf!(staging)
    end
  end

  defp file_exists?(udid, bundle, remote_path) do
    parent = Path.dirname(remote_path)
    parent = if parent == ".", do: "Documents", else: "Documents/#{parent}"

    case run_devicectl(udid, bundle, "info", "files", parent) do
      {:ok, out} -> String.contains?(out, Path.basename(remote_path))
      _ -> false
    end
  end

  defp list_remote_dir(udid, bundle, remote) do
    path = if remote == "" or remote == ".", do: "Documents", else: "Documents/#{remote}"

    case run_devicectl(udid, bundle, "info", "files", path) do
      {:ok, out} -> parse_file_list(out) |> Enum.map(fn name -> {name, 0, 0} end)
      _ -> []
    end
  end

  defp parse_file_list(out) do
    out
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "Path:")))
  end

  defp list_files(dir), do: DalaDev.FileTransfer.Sync.list_files(dir)

  defp cp_r(source, dest) do
    if File.dir?(source),
      do: File.cp_r!(source, dest),
      else:
        (
          File.mkdir_p!(Path.dirname(dest))
          File.cp!(source, dest)
        )
  end

  defp compute_sync_actions(local_map, remote_map, delete?),
    do: DalaDev.FileTransfer.Sync.compute_actions(local_map, remote_map, delete?)

  defp print_actions(actions) do
    Enum.each(actions, fn
      {:push, path} -> DalaDev.Output.info("    PUSH  #{path}")
      {:pull, path} -> DalaDev.Output.info("    PULL  #{path}")
      {:delete, path} -> DalaDev.Output.info("    DELETE  #{path}")
    end)
  end
end
