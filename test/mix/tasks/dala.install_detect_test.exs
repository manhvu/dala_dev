defmodule Mix.Tasks.Dala.InstallDetectTest do
  use ExUnit.Case, async: false

  describe "detect_android_sdk/0" do
    test "returns a path string or nil without crashing" do
      result = Mix.Tasks.Dala.Install.detect_android_sdk()
      assert is_binary(result) or is_nil(result)
    end

    test "prefers ANDROID_HOME when set to a real dir" do
      dir = Path.join("test_tmp", "fake_android_sdk_#{System.unique_integer()}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      System.put_env("ANDROID_HOME", Path.absname(dir))
      on_exit(fn -> System.delete_env("ANDROID_HOME") end)

      assert Mix.Tasks.Dala.Install.detect_android_sdk() == Path.absname(dir)
    end

    test "skips ANDROID_HOME set to a nonexistent dir" do
      previous = System.get_env("ANDROID_HOME")
      System.put_env("ANDROID_HOME", "/definitely/not/a/real/sdk")

      on_exit(fn ->
        if previous,
          do: System.put_env("ANDROID_HOME", previous),
          else: System.delete_env("ANDROID_HOME")
      end)

      result = Mix.Tasks.Dala.Install.detect_android_sdk()
      refute result == "/definitely/not/a/real/sdk"
    end
  end
end
