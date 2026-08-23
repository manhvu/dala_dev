defmodule DalaDev.FileTransfer.Platform.Simulator do
  @moduledoc "iOS Simulator file transfer via direct filesystem access."

  alias DalaDev.Device

  # ── Push ────────────────────────────────────────────────────────────────────

  @spec push(Device.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def push(%Device{serial: udid}, local, remote, opts) do
    on_conflict = Keyword.get(opts, :on_conflict, :overwrite)
    progress? = Keyword.get(opts, :progress, false)
    bundle = DalaDev.Config.bundle_id()
    docs_dir = sim_docs_dir(udid, bundle)

    if is_nil(docs_dir) do
      {:error,
       "Could not locate app Documents directory for simulator #{udid}. Is the app installed?"}
    else
      remote_abs = Path.join(docs_dir, remote)

      if File.dir?(local),
        do: push_dir(local, remote_abs, on_conflict, progress?),
        else: push_file(local, remote_abs, on_conflict)
    end
  end

  defp push_file(local, remote, on_conflict) do
    case {File.exists?(remote), on_conflict} do
      {true, :skip} ->
        {:ok, "skipped (already exists)"}

      {true, :rename} ->
        renamed = "#{remote}.#{unique()}"
        File.mkdir_p!(Path.dirname(renamed))
        File.cp!(local, renamed)
        {:ok, "saved as #{Path.basename(renamed)}"}

      _ ->
        File.mkdir_p!(Path.dirname(remote))
        File.cp!(local, remote)
        {:ok, "pushed to Documents/#{Path.basename(remote)}"}
    end
  end

  defp push_dir(local, remote, on_conflict, progress?) do
    files = list_files(local)
    if progress?, do: DalaDev.Output.info("    #{length(files)} file(s) in directory")

    case {File.exists?(remote), on_conflict} do
      {true, :skip} ->
        {:ok, "skipped (already exists)"}

      {true, :rename} ->
        renamed = "#{remote}.#{unique()}"
        cp_r(local, renamed)
        {:ok, "saved as #{Path.basename(renamed)}"}

      _ ->
        File.mkdir_p!(remote)
        cp_r(local, remote)
        {:ok, "pushed directory (#{length(files)} file(s))"}
    end
  end

  # ── Pull ────────────────────────────────────────────────────────────────────

  @spec pull(Device.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def pull(%Device{serial: udid}, remote, local, opts) do
    on_conflict = Keyword.get(opts, :on_conflict, :overwrite)
    progress? = Keyword.get(opts, :progress, false)
    bundle = DalaDev.Config.bundle_id()
    docs_dir = sim_docs_dir(udid, bundle)

    if is_nil(docs_dir) do
      {:error, "Could not locate app Documents directory for simulator #{udid}."}
    else
      remote_abs = Path.join(docs_dir, remote)

      cond do
        not File.exists?(remote_abs) -> {:error, "file not found on device: #{remote}"}
        File.dir?(remote_abs) -> pull_dir(remote_abs, local, progress?)
        true -> pull_file(remote_abs, local, on_conflict)
      end
    end
  end

  defp pull_file(remote, local, on_conflict) do
    case {File.exists?(local), on_conflict} do
      {true, :skip} ->
        {:ok, "skipped (local file already exists)"}

      {true, :rename} ->
        l = "#{local}.#{unique()}"
        File.mkdir_p!(Path.dirname(l))
        File.cp!(remote, l)
        {:ok, "pulled to #{l}"}

      _ ->
        File.mkdir_p!(Path.dirname(local))
        File.cp!(remote, local)
        {:ok, "pulled to #{local}"}
    end
  end

  defp pull_dir(remote, local, progress?) do
    files = list_files(remote)
    if progress?, do: DalaDev.Output.info("    #{length(files)} remote file(s)")
    File.mkdir_p!(local)
    cp_r(remote, local)
    {:ok, "pulled directory (#{length(files)} file(s)) to #{local}"}
  end

  # ── Ls ──────────────────────────────────────────────────────────────────────

  @spec ls(Device.t(), String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def ls(%Device{serial: udid}, remote_path) do
    bundle = DalaDev.Config.bundle_id()
    docs_dir = sim_docs_dir(udid, bundle)

    if is_nil(docs_dir) do
      {:error, "Could not locate app Documents directory for simulator #{udid}."}
    else
      remote_abs = Path.join(docs_dir, remote_path)

      case File.ls(remote_abs) do
        {:ok, files} -> {:ok, files}
        {:error, :enoent} -> {:error, "directory not found: #{remote_path}"}
        {:error, reason} -> {:error, "ls failed: #{inspect(reason)}"}
      end
    end
  end

  # ── Sync ────────────────────────────────────────────────────────────────────

  @spec sync(Device.t(), String.t(), String.t(), keyword()) ::
          {:ok, [{:push | :pull | :delete, String.t()}]} | {:error, String.t()}
  def sync(%Device{serial: udid}, local, remote, opts) do
    delete? = Keyword.get(opts, :delete, false)
    dry_run? = Keyword.get(opts, :dry_run, false)
    progress? = Keyword.get(opts, :progress, false)
    bundle = DalaDev.Config.bundle_id()
    docs_dir = sim_docs_dir(udid, bundle)

    if is_nil(docs_dir) do
      {:error, "Could not locate app Documents directory for simulator #{udid}."}
    else
      remote_abs = Path.join(docs_dir, remote)
      local_files = list_files(local)
      remote_files = list_files(remote_abs)
      local_map = Map.new(local_files, fn {rel, abs} -> {rel, File.stat!(abs)} end)
      remote_map = Map.new(remote_files, fn {rel, abs} -> {rel, File.stat!(abs)} end)
      actions = compute_sync_actions(local_map, remote_map, delete?)
      if progress? or dry_run?, do: print_actions(actions)
      if dry_run?, do: {:ok, actions}, else: execute_sync(local, remote_abs, actions)
      {:ok, actions}
    end
  end

  defp execute_sync(local, remote, actions) do
    Enum.each(actions, fn
      {:push, rel} ->
        src = Path.join(local, rel)
        dst = Path.join(remote, rel)
        File.mkdir_p!(Path.dirname(dst))
        cp_r(src, dst)

      {:delete, rel} ->
        dst = Path.join(remote, rel)
        if File.dir?(dst), do: File.rm_rf!(dst), else: File.rm!(dst)

      {:pull, _} ->
        :ok
    end)
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp sim_docs_dir(udid, bundle) do
    case System.cmd("xcrun", ["simctl", "get_app_container", udid, bundle, "data"],
           stderr_to_stdout: true
         ) do
      {path, 0} -> Path.join(String.trim(path), "Documents")
      _ -> nil
    end
  end

  defp unique, do: :erlang.unique_integer([:positive])

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
