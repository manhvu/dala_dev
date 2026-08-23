defmodule DalaDev.ConfigTest do
  use ExUnit.Case, async: false

  alias DalaDev.Config

  defp in_tmp(fun) do
    old_cwd = File.cwd!()
    dir = Path.join(System.tmp_dir!(), "dala_config_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.cd!(dir)

    try do
      fun.(dir)
    after
      File.cd!(old_cwd)
      File.rm_rf(dir)
    end
  end

  describe "load_dala_config/0" do
    test "returns [] when no dala.exs" do
      in_tmp(fn _ ->
        assert Config.load_dala_config() == []
      end)
    end

    test "reads dala_dev section from dala.exs" do
      in_tmp(fn _ ->
        File.write!("dala.exs", """
        import Config
        config :dala_dev, bundle_id: "com.acme.myapp", foo: :bar
        """)

        config = Config.load_dala_config()
        assert config[:bundle_id] == "com.acme.myapp"
        assert config[:foo] == :bar
      end)
    end

    test "returns [] when dala.exs has no dala_dev section" do
      in_tmp(fn _ ->
        File.write!("dala.exs", """
        import Config
        config :other_app, key: 1
        """)

        assert Config.load_dala_config() == []
      end)
    end
  end

  describe "bundle_id/0" do
    test "prefers dala.exs override" do
      in_tmp(fn _ ->
        File.write!("dala.exs", """
        import Config
        config :dala_dev, bundle_id: "com.override.id"
        """)

        assert Config.bundle_id() == "com.override.id"
      end)
    end

    test "falls back to iOS Info.plist CFBundleIdentifier" do
      in_tmp(fn _ ->
        File.mkdir_p!("ios")

        File.write!(Path.join("ios", "Info.plist"), """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>com.ohhi.dalademo</string>
        </dict>
        </plist>
        """)

        assert Config.bundle_id() == "com.ohhi.dalademo"
      end)
    end

    test "falls back to android gradle applicationId" do
      in_tmp(fn _ ->
        File.mkdir_p!(Path.join("android", "app"))

        File.write!(Path.join(["android", "app", "build.gradle"]), """
        android {
            defaultConfig {
                applicationId "com.example.gradleapp"
            }
        }
        """)

        assert Config.bundle_id() == "com.example.gradleapp"
      end)
    end

    test "supports gradle applicationId assignment syntax" do
      in_tmp(fn _ ->
        File.mkdir_p!(Path.join("android", "app"))

        File.write!(Path.join(["android", "app", "build.gradle"]), """
        defaultConfig {
            applicationId = "com.example.assigned"
        }
        """)

        assert Config.bundle_id() == "com.example.assigned"
      end)
    end

    test "falls back to generated default with app name" do
      in_tmp(fn _ ->
        expected = "com.example.#{Mix.Project.config()[:app]}"
        assert Config.bundle_id() == expected
      end)
    end

    test "generated default honors DALA_BUNDLE_PREFIX" do
      in_tmp(fn _ ->
        System.put_env("DALA_BUNDLE_PREFIX", "com.mycompany")

        assert Config.bundle_id() == "com.mycompany.#{Mix.Project.config()[:app]}"

        System.delete_env("DALA_BUNDLE_PREFIX")
      end)
    end

    test "empty DALA_BUNDLE_PREFIX falls back to com.example" do
      in_tmp(fn _ ->
        System.put_env("DALA_BUNDLE_PREFIX", "")

        assert Config.bundle_id() == "com.example.#{Mix.Project.config()[:app]}"

        System.delete_env("DALA_BUNDLE_PREFIX")
      end)
    end
  end
end
