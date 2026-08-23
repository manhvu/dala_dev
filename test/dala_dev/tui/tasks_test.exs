defmodule DalaDev.Tui.TasksTest do
  use ExUnit.Case, async: true

  alias DalaDev.Tui.Tasks

  describe "list/0" do
    test "returns all available tasks" do
      tasks = Tasks.list()
      assert length(tasks) > 0
    end

    test "includes device tasks" do
      tasks = Tasks.list()
      assert Enum.any?(tasks, &(&1.name == "devices"))
      assert Enum.any?(tasks, &(&1.name == "emulators"))
    end

    test "includes deploy tasks" do
      tasks = Tasks.list()
      assert Enum.any?(tasks, &(&1.name == "deploy"))
      assert Enum.any?(tasks, &(&1.name == "push"))
    end

    test "includes diagnostics tasks" do
      tasks = Tasks.list()
      assert Enum.any?(tasks, &(&1.name == "doctor"))
    end

    test "includes release tasks" do
      tasks = Tasks.list()
      assert Enum.any?(tasks, &(&1.name == "release"))
      assert Enum.any?(tasks, &(&1.name == "release.android"))
    end

    test "includes file transfer tasks" do
      tasks = Tasks.list()
      assert Enum.any?(tasks, &(&1.name == "push_file"))
      assert Enum.any?(tasks, &(&1.name == "pull_file"))
      assert Enum.any?(tasks, &(&1.name == "sync"))
    end

    test "includes dev tasks" do
      tasks = Tasks.list()
      assert Enum.any?(tasks, &(&1.name == "server"))
      assert Enum.any?(tasks, &(&1.name == "web"))
      assert Enum.any?(tasks, &(&1.name == "debug"))
      assert Enum.any?(tasks, &(&1.name == "observer"))
    end

    test "all tasks have required fields" do
      tasks = Tasks.list()
      category_keys = Enum.map(Tasks.categories(), &elem(&1, 0))

      Enum.each(tasks, fn task ->
        assert %Tasks{} = task
        assert byte_size(task.name) > 0
        assert byte_size(task.description) > 0
        # each referenced module must load and be a runnable Mix task
        assert match?({:module, _}, Code.ensure_loaded(task.module))
        assert function_exported?(task.module, :run, 1)
        assert task.category in category_keys
        assert Enum.all?(task.args, &is_binary/1)
      end)
    end

    test "task names are unique" do
      tasks = Tasks.list()
      names = Enum.map(tasks, & &1.name)
      assert length(names) == length(Enum.uniq(names))
    end
  end

  describe "by_category/1" do
    test "filters device tasks" do
      device_tasks = Tasks.by_category(:device)
      assert Enum.all?(device_tasks, &(&1.category == :device))
    end

    test "filters deploy tasks" do
      deploy_tasks = Tasks.by_category(:deploy)
      assert Enum.all?(deploy_tasks, &(&1.category == :deploy))
    end

    test "filters setup tasks" do
      setup_tasks = Tasks.by_category(:setup)
      assert Enum.all?(setup_tasks, &(&1.category == :setup))
    end

    test "filters release tasks" do
      release_tasks = Tasks.by_category(:release)
      assert Enum.all?(release_tasks, &(&1.category == :release))
    end

    test "filters dev tasks" do
      dev_tasks = Tasks.by_category(:dev)
      assert Enum.all?(dev_tasks, &(&1.category == :dev))
    end

    test "filters diagnostics tasks" do
      diag_tasks = Tasks.by_category(:diagnostics)
      assert Enum.all?(diag_tasks, &(&1.category == :diagnostics))
    end

    test "filters file transfer tasks" do
      file_tasks = Tasks.by_category(:file)
      assert Enum.all?(file_tasks, &(&1.category == :file))
    end

    test "returns empty for unknown category" do
      assert Tasks.by_category(:unknown) == []
    end

    test "returns empty for non-existent category" do
      assert Tasks.by_category(:nonexistent) == []
    end
  end

  describe "categories/0" do
    test "returns all categories" do
      categories = Tasks.categories()
      assert length(categories) > 0
      assert {:device, "Devices"} in categories
      assert {:deploy, "Deploy"} in categories
    end

    test "categories are tuples of atom and string" do
      categories = Tasks.categories()

      Enum.each(categories, fn {atom, label} ->
        assert byte_size(Atom.to_string(atom)) > 0
        assert byte_size(label) > 0
      end)
    end

    test "includes all expected categories" do
      categories = Tasks.categories()
      keys = Enum.map(categories, &elem(&1, 0))

      assert :device in keys
      assert :deploy in keys
      assert :setup in keys
      assert :release in keys
      assert :dev in keys
      assert :diagnostics in keys
      assert :file in keys
    end
  end

  describe "category_label/1" do
    test "returns human-readable labels" do
      assert Tasks.category_label(:device) == "Devices"
      assert Tasks.category_label(:deploy) == "Deploy"
      assert Tasks.category_label(:setup) == "Setup"
      assert Tasks.category_label(:release) == "Release"
      assert Tasks.category_label(:dev) == "Development"
      assert Tasks.category_label(:diagnostics) == "Diagnostics"
      assert Tasks.category_label(:file) == "File Transfer"
    end

    test "returns string for unknown" do
      assert Tasks.category_label(:unknown) == "unknown"
    end

    test "returns string for arbitrary atom" do
      assert Tasks.category_label(:something_else) == "something_else"
    end
  end

  describe "task structure" do
    test "each task has a valid module reference" do
      tasks = Tasks.list()

      Enum.each(tasks, fn task ->
        # Module should load and resolve to a runnable Mix task
        assert match?({:module, _}, Code.ensure_loaded(task.module))
        assert function_exported?(task.module, :run, 1)
      end)
    end

    test "each task has a non-empty description" do
      tasks = Tasks.list()

      Enum.each(tasks, fn task ->
        assert String.length(task.description) > 0
      end)
    end
  end
end
