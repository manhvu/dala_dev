defmodule DalaDev.NativeBuildToolchainTest do
  use ExUnit.Case, async: true

  alias DalaDev.NativeBuild

  describe "ios_toolchain_available?/0" do
    test "mirrors macOS host + xcrun presence" do
      expected = match?({:unix, :darwin}, :os.type()) and System.find_executable("xcrun") != nil
      assert NativeBuild.ios_toolchain_available?() == expected
    end
  end

  describe "android_toolchain_available?/1" do
    test "false when project has no android dir" do
      dir = Path.join("test_tmp", "no_android_#{System.unique_integer()}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      # No android/local.properties → read_sdk_dir fails → deterministically false
      refute NativeBuild.android_toolchain_available?(Path.absname(dir))
    end

    test "true when adb + sdk.dir pointing at real dir both exist" do
      if System.find_executable("adb") do
        uid = System.unique_integer()
        dir = Path.join("test_tmp", "with_android_#{uid}")
        sdk = Path.join("test_tmp", "real_sdk_#{uid}")
        File.mkdir_p!(Path.join(dir, "android"))
        File.mkdir_p!(sdk)
        on_exit(fn -> File.rm_rf!(dir) end)

        File.write!(
          Path.join([dir, "android", "local.properties"]),
          "sdk.dir=#{File.cwd!() |> Path.absname() |> Path.join(sdk)}\n"
        )

        assert NativeBuild.android_toolchain_available?(Path.absname(dir))
      end
    end
  end

  describe "__load_config_in__/1" do
    test "raises when the project dir has no dala.exs" do
      dir = Path.join("test_tmp", "no_dala_exs_#{System.unique_integer()}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      # Uses the explicit-dir seam so the VM-global CWD is never mutated
      # (File.cd!/2 here races with parallel compilation of other test files).
      assert catch_error(NativeBuild.__load_config_in__(Path.absname(dir)))
    end

    test "__load_config__/0 still reads from the real project root" do
      # The repo root has mix.exs but no dala.exs → same contract as before.
      assert catch_error(NativeBuild.__load_config__())
    end
  end
end
