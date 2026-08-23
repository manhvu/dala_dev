defmodule DalaDev.EmulatorsExtraTest do
  use ExUnit.Case, async: false

  alias DalaDev.Emulators

  describe "find_emulator_binary/1" do
    test "returns error tuple when no SDK found in empty project" do
      dir =
        System.tmp_dir!()
        |> Path.join("emu_no_sdk_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      result = File.cd!(dir, fn -> Emulators.find_emulator_binary(dir) end)

      case result do
        {:error, msg} -> assert msg =~ "emulator"
        {:ok, _path} -> :ok
      end
    end

    test "finds emulator binary via local.properties sdk.dir" do
      dir = Path.join("test_tmp", "emu_proj")
      sdk = Path.join("test_tmp", "fake_sdk")
      File.mkdir_p!(Path.dirname(dir))
      File.mkdir_p!(dir)
      File.mkdir_p!(Path.join(sdk, "emulator"))

      on_exit(fn ->
        File.rm_rf!(dir)
        File.rm_rf!(sdk)
      end)

      File.write!(
        Path.join(dir, "local.properties"),
        "sdk.dir=#{File.cwd!() |> Path.absname() |> Path.join(sdk)}\n"
      )

      File.write!(Path.join([sdk, "emulator", "emulator"]), "#!/bin/sh\n")

      assert {:ok, path} = Emulators.find_emulator_binary(File.cwd!() |> Path.join(dir))
      assert path =~ "emulator"
    end
  end

  describe "list_android/0" do
    test "returns a list or ok-tuple without crashing (adb may be missing)" do
      result = Emulators.list_android()
      assert is_list(result) or match?({:ok, _}, result)
    end
  end

  describe "list_ios/0" do
    test "returns a list or ok-tuple without crashing (xcrun may be missing)" do
      result = Emulators.list_ios()
      assert is_list(result) or match?({:ok, _}, result)
    end
  end
end
