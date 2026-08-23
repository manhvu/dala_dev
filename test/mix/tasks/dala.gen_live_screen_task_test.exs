defmodule Mix.Tasks.Dala.GenLiveScreenTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  defp scaffold_project do
    dir =
      System.tmp_dir!()
      |> Path.join("dala_gen_live_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    File.write!(Path.join([dir, "mix.exs"]), """
    defmodule GenApp.MixProject do
      use Mix.Project
      def project do
        [app: :gen_app, version: "0.1.0"]
      end
    end
    """)

    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  describe "run/1" do
    test "raises with usage when no name given" do
      assert catch_error(Mix.Tasks.Dala.Gen.LiveScreen.run([]))
    end

    test "raises when not in a mix project" do
      empty =
        System.tmp_dir!()
        |> Path.join("dala_gen_empty_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(empty)
      on_exit(fn -> File.rm_rf!(empty) end)

      assert catch_error(
               File.cd!(empty, fn ->
                 Mix.Tasks.Dala.Gen.LiveScreen.run(["MyScreen"])
               end)
             )
    end

    test "generates LiveView + Screen files in a scaffolded project" do
      dir = scaffold_project()

      output =
        capture_io(fn ->
          File.cd!(dir, fn ->
            Mix.Tasks.Dala.Gen.LiveScreen.run(["Settings"])
          end)
        end)

      assert output =~ "Settings" or output =~ "Generated" or output =~ "Created"
      # Some generated file should exist somewhere in the project
      generated = Path.wildcard(Path.join(dir, "**/*.ex"))
      assert generated != []
    end
  end
end
