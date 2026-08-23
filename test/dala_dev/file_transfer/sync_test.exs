defmodule DalaDev.FileTransfer.SyncTest do
  use ExUnit.Case, async: true

  alias DalaDev.FileTransfer.Sync

  describe "compute_actions/3" do
    test "pushes local-only files" do
      local = %{"a.txt" => %{size: 10, mtime: 100}}
      remote = %{}

      assert [{:push, "a.txt"}] = Sync.compute_actions(local, remote, false)
    end

    test "deletes remote-only files only when delete is enabled" do
      local = %{}
      remote = %{"old.txt" => {5, 50}}

      assert [] = Sync.compute_actions(local, remote, false)
      assert [{:delete, "old.txt"}] = Sync.compute_actions(local, remote, true)
    end

    test "pushes when sizes differ" do
      local = %{"a.txt" => %{size: 20, mtime: 100}}
      remote = %{"a.txt" => {10, 200}}

      assert [{:push, "a.txt"}] = Sync.compute_actions(local, remote, false)
    end

    test "pulls when remote is newer and same size" do
      local = %{"a.txt" => %{size: 10, mtime: 100}}
      remote = %{"a.txt" => {10, 200}}

      assert [{:pull, "a.txt"}] = Sync.compute_actions(local, remote, false)
    end

    test "no action when files are identical" do
      local = %{"a.txt" => %{size: 10, mtime: 100}}
      remote = %{"a.txt" => {10, 100}}

      assert [] = Sync.compute_actions(local, remote, true)
    end

    test "handles non-integer mtimes without crashing" do
      local = %{"a.txt" => %{size: 10, mtime: nil}}
      remote = %{"a.txt" => {10, :unknown}}

      assert [] = Sync.compute_actions(local, remote, false)
    end

    test "combines push, pull, and delete actions" do
      local = %{
        "new.txt" => %{size: 1, mtime: 1},
        "newer.txt" => %{size: 2, mtime: 300},
        "same.txt" => %{size: 3, mtime: 3}
      }

      remote = %{
        "older.txt" => {2, 100},
        "remote_only.txt" => {9, 9},
        "newer.txt" => {2, 100},
        "same.txt" => {3, 3}
      }

      actions = Sync.compute_actions(local, remote, true) |> Enum.sort()

      assert actions == [
               {:delete, "older.txt"},
               {:delete, "remote_only.txt"},
               {:push, "new.txt"},
               {:push, "newer.txt"}
             ]
    end
  end

  describe "list_files/1" do
    test "lists regular files with relative paths" do
      dir = Path.join("test_tmp", "sync_list")
      File.mkdir_p!(Path.join(dir, "sub"))
      # Scope cleanup to this test's own subtree — never rm_rf the shared
      # "test_tmp" root, which races with other async tests using it.
      on_exit(fn -> File.rm_rf!(dir) end)

      File.write!(Path.join(dir, "root.txt"), "r")
      File.write!(Path.join([dir, "sub", "nested.txt"]), "n")

      files = Sync.list_files(dir) |> Enum.sort()
      assert [{"root.txt", root_path}, {"sub/nested.txt", nested_path}] = files
      assert root_path == Path.join(dir, "root.txt")
      assert nested_path == Path.join([dir, "sub", "nested.txt"])
    end

    test "returns empty list for missing dir" do
      assert [] = Sync.list_files("/nonexistent/dir")
    end
  end
end
