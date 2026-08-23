defmodule DalaDev.FileTransfer.Platform.Android do
  @moduledoc "Android file transfer via adb push/pull/run-as."

  alias DalaDev.Device

  # Compiled at module-attribute expansion time via
  # `DalaDev.Utils.compile_regex/2` (compile-time regex sigil literals are unsafe
  # on Elixir 1.19 / OTP 28.0+).
  @whitespace_split DalaDev.Utils.compile_regex("\\s+")

  # ── Push ────────────────────────────────────────────────────────────────────

  @spec push(Device.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def push(%Device{serial: serial}, local, remote, opts) do
    on_conflict = Keyword.get(opts, :on_conflict, :overwrite)
    progress? = Keyword.get(opts, :progress, false)
    pkg = DalaDev.Config.bundle_id()
    remote_abs = resolve_remote(remote, "/data/data/#{pkg}/files")

    if File.exists?(local) do
      rooted? = rooted?(serial)
      mkdir(serial, pkg, Path.dirname(remote_abs), rooted?)

      if File.dir?(local) do
        push_dir(serial, pkg, local, remote_abs, rooted?, on_conflict, progress?)
      else
        push_file(serial, pkg, local, remote_abs, rooted?, on_conflict)
      end
    else
      {:error, "local path does not exist: #{local}"}
    end
  catch
    {:error, reason} -> {:error, reason}
  end

  defp push_file(serial, pkg, local, remote, rooted?, on_conflict) do
    tmp = staged("push")
    adb_push(serial, local, tmp)

    case {file_exists?(serial, pkg, remote, rooted?), on_conflict} do
      {true, :skip} ->
        adb_shell(serial, "rm -f #{tmp}")
        {:ok, "skipped (already exists)"}

      {true, :rename} ->
        renamed = "#{remote}.#{unique()}"
        mv_sandbox(serial, pkg, tmp, renamed, rooted?)
        {:ok, "saved as #{Path.basename(renamed)}"}

      _ ->
        mv_sandbox(serial, pkg, tmp, remote, rooted?)
        {:ok, "pushed to #{remote}"}
    end
  end

  defp push_dir(serial, pkg, local, remote, rooted?, on_conflict, progress?) do
    files = list_files(local)
    if progress?, do: DalaDev.Output.info("    #{length(files)} file(s) in directory")

    stage_local = Path.join(System.tmp_dir!(), "dala_push_#{serial}.tar")
    stage_dev = "/data/local/tmp/dala_push.tar"

    try do
      create_tar(stage_local, local)
      adb_push(serial, stage_local, stage_dev)

      case on_conflict do
        :skip ->
          new_count =
            Enum.count(files, fn {rel, _} ->
              not file_exists?(serial, pkg, "#{remote}/#{rel}", rooted?)
            end)

          if new_count == 0 do
            adb_shell(serial, "rm -f #{stage_dev}")
            {:ok, "all files skipped (already exist)"}
          else
            extract_tar(serial, pkg, stage_dev, remote, rooted?)
            {:ok, "pushed #{new_count} new file(s), skipped existing"}
          end

        _ ->
          extract_tar(serial, pkg, stage_dev, remote, rooted?)
          {:ok, "pushed directory (#{length(files)} file(s)) to #{remote}"}
      end
    catch
      {:error, reason} -> {:error, reason}
    after
      File.rm(stage_local)
    end
  end

  # ── Pull ────────────────────────────────────────────────────────────────────

  @spec pull(Device.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def pull(%Device{serial: serial}, remote, local, opts) do
    on_conflict = Keyword.get(opts, :on_conflict, :overwrite)
    progress? = Keyword.get(opts, :progress, false)
    pkg = DalaDev.Config.bundle_id()
    remote_abs = resolve_remote(remote, "/data/data/#{pkg}/files")
    rooted? = rooted?(serial)

    if dir_exists?(serial, pkg, remote_abs, rooted?) do
      pull_dir(serial, pkg, remote_abs, local, rooted?, progress?)
    else
      case {File.exists?(local), on_conflict} do
        {true, :skip} -> {:ok, "skipped (local file already exists)"}
        {true, :rename} -> do_pull(serial, pkg, remote_abs, "#{local}.#{unique()}", rooted?)
        _ -> do_pull(serial, pkg, remote_abs, local, rooted?)
      end
    end
  end

  defp pull_dir(serial, pkg, remote, local, rooted?, progress?) do
    remote_files = ls_dir(serial, pkg, remote, rooted?)
    if progress?, do: DalaDev.Output.info("    #{length(remote_files)} remote file(s)")

    stage_local = Path.join(System.tmp_dir!(), "dala_pull_#{serial}.tar")
    stage_dev = "/data/local/tmp/dala_pull.tar"

    try do
      tar_cmd =
        if rooted?,
          do: "tar cf #{stage_dev} -C #{remote} .",
          else: "run-as #{pkg} tar cf #{stage_dev} -C #{remote} ."

      adb_shell(serial, tar_cmd)
      adb_pull(serial, stage_dev, stage_local)
      adb_shell(serial, "rm -f #{stage_dev}")
      File.mkdir_p!(local)

      case :erl_tar.extract(String.to_charlist(stage_local), [
             :compressed,
             cwd: String.to_charlist(local)
           ]) do
        :ok -> {:ok, "pulled directory (#{length(remote_files)} file(s)) to #{local}"}
        {:error, reason} -> {:error, "tar extract failed: #{inspect(reason)}"}
      end
    catch
      {:error, reason} -> {:error, reason}
    after
      File.rm(stage_local)
    end
  end

  defp do_pull(serial, pkg, remote, local, rooted?) do
    tmp = staged("pull")

    copy_cmd =
      if rooted?, do: "cp #{remote} #{tmp}", else: "run-as #{pkg} cp #{remote} #{tmp} 2>/dev/null"

    case adb_shell(serial, copy_cmd) do
      {:ok, _} -> :ok
      {:error, _} -> throw({:error, "file not found on device: #{remote}"})
    end

    File.mkdir_p!(Path.dirname(local))

    case adb_pull(serial, tmp, local) do
      :ok ->
        adb_shell(serial, "rm -f #{tmp}")
        {:ok, "pulled to #{local}"}

      {:error, reason} ->
        adb_shell(serial, "rm -f #{tmp}")
        {:error, "adb pull failed: #{reason}"}
    end
  catch
    {:error, reason} -> {:error, reason}
  end

  # ── Ls ──────────────────────────────────────────────────────────────────────

  @spec ls(Device.t(), String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def ls(%Device{serial: serial}, remote_path) do
    pkg = DalaDev.Config.bundle_id()
    remote_abs = resolve_remote(remote_path, "/data/data/#{pkg}/files")
    rooted? = rooted?(serial)
    cmd = if rooted?, do: "ls -1 #{remote_abs}", else: "run-as #{pkg} ls -1 #{remote_abs}"

    case adb_shell(serial, cmd) do
      {:ok, out} ->
        {:ok, out |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))}

      {:error, reason} ->
        {:error, "ls failed: #{reason}"}
    end
  end

  # ── Sync ────────────────────────────────────────────────────────────────────

  @spec sync(Device.t(), String.t(), String.t(), keyword()) ::
          {:ok, [{:push | :pull | :delete, String.t()}]} | {:error, String.t()}
  def sync(%Device{serial: serial}, local, remote, opts) do
    delete? = Keyword.get(opts, :delete, false)
    dry_run? = Keyword.get(opts, :dry_run, false)
    progress? = Keyword.get(opts, :progress, false)
    pkg = DalaDev.Config.bundle_id()
    remote_abs = resolve_remote(remote, "/data/data/#{pkg}/files")
    rooted? = rooted?(serial)

    local_files = list_files(local)
    remote_files = ls_dir_with_meta(serial, pkg, remote_abs, rooted?)
    local_map = Map.new(local_files, fn {rel, abs} -> {rel, File.stat!(abs)} end)
    remote_map = Map.new(remote_files, fn {rel, size, mtime} -> {rel, {size, mtime}} end)
    actions = compute_sync_actions(local_map, remote_map, delete?)

    if progress? or dry_run?, do: print_actions(actions)

    if dry_run? do
      {:ok, actions}
    else
      execute_sync(serial, pkg, local, remote_abs, actions, rooted?)
      {:ok, actions}
    end
  end

  defp execute_sync(serial, pkg, local, remote, actions, rooted?) do
    Enum.each(actions, fn
      {:push, rel} ->
        abs_local = Path.join(local, rel)
        abs_remote = "#{remote}/#{rel}"
        mkdir(serial, pkg, Path.dirname(abs_remote), rooted?)
        tmp = staged("sync")
        adb_push(serial, abs_local, tmp)
        mv_sandbox(serial, pkg, tmp, abs_remote, rooted?)

      {:delete, rel} ->
        abs_remote = "#{remote}/#{rel}"
        cmd = if rooted?, do: "rm -f #{abs_remote}", else: "run-as #{pkg} rm -f #{abs_remote}"
        adb_shell(serial, cmd)

      {:pull, _} ->
        :ok
    end)
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp resolve_remote(remote, app_files),
    do: if(String.starts_with?(remote, "/"), do: remote, else: "#{app_files}/#{remote}")

  defp staged(prefix), do: "/data/local/tmp/dala_#{prefix}_#{unique()}"
  defp unique, do: :erlang.unique_integer([:positive])

  defp rooted?(serial) do
    case adb(serial, ["root"]) do
      {:ok, out} -> out =~ "restarting" or out =~ "already running as root"
      _ -> false
    end
  end

  defp mkdir(serial, pkg, dir, rooted?) do
    cmd = if rooted?, do: "mkdir -p #{dir}", else: "run-as #{pkg} mkdir -p #{dir}"

    case adb_shell(serial, cmd) do
      {:ok, _} -> :ok
      {:error, reason} -> throw({:error, "mkdir failed: #{reason}"})
    end
  end

  defp mv_sandbox(serial, pkg, tmp, dest, rooted?) do
    cmd =
      if rooted?,
        do: "mv #{tmp} #{dest}",
        else: "run-as #{pkg} cp #{tmp} #{dest} 2>/dev/null; rm -f #{tmp}"

    adb_shell(serial, cmd)
  end

  defp file_exists?(serial, pkg, path, rooted?) do
    cmd = if rooted?, do: "test -f #{path}", else: "run-as #{pkg} test -f #{path}"
    match?({:ok, _}, adb_shell(serial, cmd))
  end

  defp dir_exists?(serial, pkg, path, rooted?) do
    cmd = if rooted?, do: "test -d #{path}", else: "run-as #{pkg} test -d #{path}"
    match?({:ok, _}, adb_shell(serial, cmd))
  end

  defp extract_tar(serial, pkg, stage_dev, remote, rooted?) do
    cmd =
      if rooted?,
        do: "tar xf #{stage_dev} -C #{Path.dirname(remote)} 2>/dev/null; rm -f #{stage_dev}",
        else:
          "run-as #{pkg} tar xf #{stage_dev} -C #{Path.dirname(remote)} 2>/dev/null; rm -f #{stage_dev}"

    case adb_shell(serial, cmd) do
      {:ok, _} -> :ok
      {:error, reason} -> throw({:error, "extract failed: #{reason}"})
    end
  end

  defp ls_dir(serial, pkg, remote, rooted?) do
    cmd = if rooted?, do: "ls -1 #{remote}", else: "run-as #{pkg} ls -1 #{remote}"

    case adb_shell(serial, cmd) do
      {:ok, out} ->
        out |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

      {:error, _} ->
        []
    end
  end

  defp ls_dir_with_meta(serial, pkg, remote, rooted?) do
    cmd = if rooted?, do: "ls -l #{remote}", else: "run-as #{pkg} ls -l #{remote}"

    case adb_shell(serial, cmd) do
      {:ok, out} ->
        out
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(fn line ->
          case String.split(line, @whitespace_split, parts: 9) do
            [_p, _n, _o, _g, size, _d, _t, name | _] -> {name, parse_int(size), 0}
            _ -> {line, 0, 0}
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp parse_int(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp list_files(dir), do: DalaDev.FileTransfer.Sync.list_files(dir)

  defp create_tar(stage_local, local) do
    case System.cmd("tar", ["cf", stage_local, "-C", Path.dirname(local), Path.basename(local)],
           env: [{"COPYFILE_DISABLE", "1"}],
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {out, _} -> throw({:error, "tar create failed: #{out}"})
    end
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

  # ── ADB wrappers ────────────────────────────────────────────────────────────

  defp adb(serial, args) do
    case System.cmd("adb", ["-s", serial | args], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _} -> {:error, String.trim(output)}
    end
  end

  defp adb_shell(serial, cmd), do: adb(serial, ["shell", cmd])
  defp adb_push(serial, local, remote), do: adb(serial, ["push", local, remote])

  defp adb_pull(serial, remote, local) do
    case adb(serial, ["pull", remote, local]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
