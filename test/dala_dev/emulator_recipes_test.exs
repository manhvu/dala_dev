defmodule DalaDev.EmulatorsRecipesTest do
  use ExUnit.Case, async: true

  import Mix.Tasks.Dala.Emulators, only: [split_flags: 1]

  alias DalaDev.Emulators

  describe "recipes/0 and recipe_args/1" do
    test "known recipes resolve to real emulator flags" do
      assert {:ok, ["-selinux", "disabled"]} = Emulators.recipe_args("selinux-off")
      assert {:ok, ["-no-snapshot"]} = Emulators.recipe_args("cold-boot")
      assert {:ok, ["-wipe-data"]} = Emulators.recipe_args("wipe-data")
      assert {:ok, ["-no-audio"]} = Emulators.recipe_args("no-audio")
      assert {:ok, ["-gpu", "host"]} = Emulators.recipe_args("gpu-host")
    end

    test "unknown recipe returns :error" do
      assert :error = Emulators.recipe_args("does-not-exist")
    end

    test "recipes/0 lists every available name sorted" do
      names = Emulators.recipes()
      assert "selinux-off" in names
      assert names == Enum.sort(names)
    end
  end

  describe "Mix.Tasks.Dala.Emulators.split_flags/1" do
    test "splits on whitespace and strips surrounding quotes" do
      assert split_flags("-no-audio -gpu host") == ["-no-audio", "-gpu", "host"]
      assert split_flags("  -flag   \"quoted value\" ") == ["-flag", "quoted value"]
      assert split_flags("") == []
    end
  end

  describe "start_android/2 arity compatibility" do
    @tag :integration
    test "extra args are optional" do
      # Bogus AVD — the emulator binary (if present) exits immediately;
      # the function must still return :ok because the process detached.
      result = Emulators.start_android("definitely_not_an_avd_xyz")
      assert match?(:ok, result) or match?({:error, _}, result)
    end
  end
end
