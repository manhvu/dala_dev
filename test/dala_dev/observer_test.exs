defmodule DalaDev.ObserverTest do
  use ExUnit.Case, async: false
  doctest DalaDev.Observer

  alias DalaDev.Observer

  describe "observe/2" do
    test "returns system info for local node" do
      assert {:ok, data} = Observer.observe(Node.self())
      assert data[:node] == Node.self()

      assert %{memory: %{total: mem_total}, process_count: process_count} = data.system
      assert mem_total > 0
      assert is_integer(process_count) and process_count > 0

      assert %DateTime{} = data[:timestamp]
    end

    test "returns process list" do
      assert {:ok, %{processes: [proc | _]}} = Observer.observe(Node.self())

      # Check process info structure
      assert Map.has_key?(proc, :pid)
      assert Map.has_key?(proc, :memory)
      assert Map.has_key?(proc, :reductions)
      assert Map.has_key?(proc, :message_queue_len)
      assert Map.has_key?(proc, :current_function)
      assert Map.has_key?(proc, :status)
    end

    test "returns ETS tables" do
      assert {:ok, %{ets_tables: [table | _]}} = Observer.observe(Node.self())

      # Check ETS table structure
      assert Map.has_key?(table, :id)
      assert Map.has_key?(table, :name)
      assert Map.has_key?(table, :type)
      assert Map.has_key?(table, :size)
      assert Map.has_key?(table, :memory)
    end

    test "returns applications list" do
      assert {:ok, %{applications: [app | _]}} = Observer.observe(Node.self())

      # Check application structure
      assert Map.has_key?(app, :name)
      assert Map.has_key?(app, :description)
      assert Map.has_key?(app, :version)
    end

    test "returns modules info" do
      assert {:ok, data} = Observer.observe(Node.self())
      assert %{count: count, total_memory: _} = data.modules
      assert is_integer(count) and count > 0
    end

    test "returns ports info" do
      assert {:ok, %{ports: [port | _]}} = Observer.observe(Node.self())
      assert Map.has_key?(port, :id)
      assert Map.has_key?(port, :name)
    end

    test "returns load info" do
      assert {:ok, data} = Observer.observe(Node.self())
      assert %{io: _, scheduler_usage: _} = data.load
    end
  end

  describe "system_info/2" do
    test "returns system information" do
      info = Observer.system_info(Node.self())

      assert %{
               memory: %{total: total},
               uptime_ms: uptime_ms,
               process_count: process_count,
               ets_tables_count: ets_count
             } = info

      assert total > 0
      assert uptime_ms >= 0
      assert is_integer(process_count) and process_count > 0
      assert is_integer(ets_count) and ets_count >= 0
      assert info.system_version =~ "OTP"
    end
  end

  describe "process_list/2" do
    test "returns list of processes" do
      processes = Observer.process_list(Node.self())
      assert [_ | _] = processes
    end

    test "processes are sorted by memory descending" do
      processes = Observer.process_list(Node.self())
      memories = Enum.map(processes, & &1.memory)
      assert memories == Enum.sort(memories, &(&1 >= &2))
    end
  end

  describe "ets_tables/2" do
    test "returns list of ETS tables" do
      tables = Observer.ets_tables(Node.self())
      assert [_ | _] = tables
    end

    test "ETS tables are sorted by memory descending" do
      tables = Observer.ets_tables(Node.self())

      if length(tables) > 1 do
        memories = Enum.map(tables, & &1.memory)
        assert memories == Enum.sort(memories, &(&1 >= &2))
      end
    end
  end

  describe "remote node observation" do
    test "handles unreachable node gracefully" do
      # Try to observe a non-existent node
      result = Observer.observe(:"non_existent_node@127.0.0.1")
      # Should either fail with error or return error in data
      case result do
        {:error, _reason} -> :ok
        {:ok, _} -> :ok
        other -> flunk("Expected error but got: #{inspect(other)}")
      end
    end
  end
end
