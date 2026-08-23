defmodule Mix.Tasks.Dala.EnableTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  defp scaffold_project do
    dir =
      System.tmp_dir!()
      |> Path.join("dala_enable_task_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(Path.join([dir, "ios"]))
    File.mkdir_p!(Path.join([dir, "android"]))

    File.write!(Path.join([dir, "mix.exs"]), """
    defmodule TestApp.MixProject do
      use Mix.Project
      def project do
        [app: :test_app, version: "0.1.0"]
      end
    end
    """)

    File.write!(Path.join([dir, "ios", "Info.plist"]), """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDisplayName</key>
      <string>TestApp</string>
    </dict>
    </plist>
    """)

    File.write!(Path.join([dir, "android", "AndroidManifest.xml"]), """
    <manifest xmlns:android="http://schemas.android.com/apk/res/android">
      <application android:label="TestApp">
      </application>
    </manifest>
    """)

    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  describe "run/1" do
    test "enables a simple feature (file_sharing) in a scaffolded project" do
      dir = scaffold_project()

      output =
        capture_io(fn ->
          File.cd!(dir, fn ->
            Mix.Tasks.Dala.Enable.run(["file_sharing"])
          end)
        end)

      assert output =~ "file_sharing"
      assert output =~ "Done"
      plist = File.read!(Path.join([dir, "ios", "Info.plist"]))
      assert plist =~ "UIFileSharingEnabled"
    end

    test "raises for unknown feature" do
      dir = scaffold_project()

      assert catch_error(
               File.cd!(dir, fn ->
                 Mix.Tasks.Dala.Enable.run(["not_a_feature"])
               end)
             )
    end

    test "raises with usage when no features given" do
      assert catch_error(Mix.Tasks.Dala.Enable.run([]))
    end

    test "raises when not in a mix project" do
      empty =
        System.tmp_dir!() |> Path.join("dala_enable_empty_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(empty)
      on_exit(fn -> File.rm_rf!(empty) end)

      assert catch_error(
               File.cd!(empty, fn ->
                 Mix.Tasks.Dala.Enable.run(["camera"])
               end)
             )
    end
  end
end
