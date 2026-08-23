defmodule DalaDev.FileTransfer.Sync do
  @moduledoc """
  Pure sync-action computation shared by all file-transfer platforms.

  Compares local and remote file maps and returns a list of actions:

    * `{:push, relative_path}` — local is new or newer
    * `{:pull, relative_path}` — remote is newer
    * `{:delete, relative_path}` — remote-only file (when delete enabled)

  Local map: `%{relative_path => %{size: integer, mtime: integer}}`
  Remote map: `%{relative_path => {size, mtime}}`

  Public for testing (see AGENTS.md "Public API Seams").
  """

  @doc """
  Computes sync actions from local and remote file maps.
  """
  @spec compute_actions(
          %{String.t() => map()},
          %{String.t() => {integer(), integer()}},
          boolean()
        ) ::
          [{:push | :pull | :delete, String.t()}]
  def compute_actions(local_map, remote_map, delete?) do
    local_keys = Map.keys(local_map) |> MapSet.new()
    remote_keys = Map.keys(remote_map) |> MapSet.new()
    push_keys = MapSet.difference(local_keys, remote_keys)
    only_remote = MapSet.difference(remote_keys, local_keys)
    delete_actions = if delete?, do: Enum.map(only_remote, &{:delete, &1}), else: []

    update_actions =
      Enum.flat_map(MapSet.intersection(local_keys, remote_keys), fn key ->
        local_stat = Map.get(local_map, key)
        {remote_size, remote_mtime} = Map.get(remote_map, key)

        cond do
          local_stat.size != remote_size ->
            [{:push, key}]

          is_integer(local_stat.mtime) and is_integer(remote_mtime) and
              local_stat.mtime > remote_mtime ->
            [{:push, key}]

          is_integer(remote_mtime) and is_integer(local_stat.mtime) and
              remote_mtime > local_stat.mtime ->
            [{:pull, key}]

          true ->
            []
        end
      end)

    Enum.map(push_keys, &{:push, &1}) ++ update_actions ++ delete_actions
  end

  @doc """
  Lists regular files under `dir` as `{relative_path, absolute_path}` pairs.
  """
  @spec list_files(String.t()) :: [{String.t(), String.t()}]
  def list_files(dir) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(fn p -> {Path.relative_to(p, dir), p} end)
  end
end
