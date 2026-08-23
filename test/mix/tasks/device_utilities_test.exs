defmodule Mix.Tasks.DeviceUtilitiesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @bogus_device "DEFINITELY_NOT_A_DEVICE_XYZ"

  # Toolchain warnings may precede the JSON document on stdout; grab the line
  # that actually starts the object.
  defp decode_json_line(out) do
    line =
      out
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(String.trim(&1), "{"))

    JSON.decode(line || "")
  end

  # ── dala.env ────────────────────────────────────────────────────────────────

  test "dala.env prints the summary sections" do
    out = capture_io(fn -> Mix.Tasks.Dala.Env.run([]) end)
    assert out =~ "Host"
    assert out =~ "Android"
    assert out =~ "Devices"
  end

  test "dala.env --json emits a single JSON document" do
    out = capture_io(fn -> Mix.Tasks.Dala.Env.run(["--json"]) end)
    assert {:ok, decoded} = decode_json_line(out)
    assert Map.has_key?(decoded, "host")
    assert Map.has_key?(decoded, "devices")
  end

  describe "Dala.Env.print_summary/1" do
    defp snapshot_with(devices, ios) do
      %{
        host: %{os: "macOS", elixir: "1.19.5", otp: "29", developer_dir: "/Xcode"},
        android: %{adb: "41.0", sdk_home: "/sdk", emulator: nil},
        ios: ios,
        project: %{name: "demo", bundle_id: "com.example.demo", dala_exs_keys: [:beam_flags]},
        devices: devices
      }
    end

    @ios_available %{available: true, xcrun: "72.", ios_sim_runtimes: 3}

    test "renders tool rows, runtimes and device lines" do
      out =
        capture_io(fn ->
          Mix.Tasks.Dala.Env.print_summary(
            snapshot_with(
              [
                %{
                  name: "Pixel",
                  id: "5554",
                  platform: :android,
                  type: :emulator,
                  status: :discovered,
                  node: :"app_android@127.0.0.1",
                  dist_port: 9100
                }
              ],
              @ios_available
            )
          )
        end)

      assert out =~ "OS      macOS"
      assert out =~ "adb           41.0"
      assert out =~ "ANDROID_HOME  /sdk"
      assert out =~ "xcrun         72."
      assert out =~ "3 iOS simulator runtime(s)"
      assert out =~ "bundle_id     com.example.demo"
      assert out =~ "Pixel  5554"
      refute out =~ "(none connected)"
    end

    test "nil tools and empty devices render gracefully" do
      out =
        capture_io(fn ->
          Mix.Tasks.Dala.Env.print_summary(snapshot_with([], %{available: false}))
        end)

      assert out =~ "(not available on this host)"
      assert out =~ "(none connected)"
      # ANDROID_HOME is set in this fixture; emulator is nil so its row is absent
      refute out =~ "emulator"
    end
  end

  # ── dala.port ───────────────────────────────────────────────────────────────

  test "dala.port prints the map or the no-devices notice" do
    out = capture_io(fn -> Mix.Tasks.Dala.Port.run([]) end)
    assert out =~ ~r(No devices connected|4369)
  end

  test "dala.port --json is machine-readable when devices exist" do
    out = capture_io(fn -> Mix.Tasks.Dala.Port.run(["--json"]) end)

    case JSON.decode(String.trim(out)) do
      {:ok, %{"ports" => ports}} when is_list(ports) -> :ok
      _ -> assert out =~ "No devices connected"
    end
  end

  # ── dala.shell ──────────────────────────────────────────────────────────────

  test "dala.shell reports unmatched devices for open and exec forms" do
    for args <- [[], ["--exec", "ls"]] do
      out =
        capture_io(fn ->
          Mix.Tasks.Dala.Shell.run(args ++ ["--device", @bogus_device])
        end)

      assert out =~ ~s(no device matched)
      assert out =~ "mix dala.devices"
    end
  end

  # ── dala.clipboard ──────────────────────────────────────────────────────────

  test "dala.clipboard get/set surface resolution errors" do
    for args <- [["get"], ["set", "text"]] do
      out =
        capture_io(fn ->
          Mix.Tasks.Dala.Clipboard.run(args ++ ["--device", @bogus_device])
        end)

      assert out =~ ~s(no device matched)
    end
  end

  test "dala.clipboard rejects bad usage" do
    assert_raise Mix.Error, ~r/Usage: mix dala.clipboard/, fn ->
      capture_io(fn -> Mix.Tasks.Dala.Clipboard.run(["frobnicate"]) end)
    end
  end

  # ── dala.link ───────────────────────────────────────────────────────────────

  test "dala.link rejects scheme-less URLs before touching devices" do
    out =
      capture_io(fn ->
        catch_exit(Mix.Tasks.Dala.Link.run(["not-a-url"]))
      end)

    assert out =~ "no URL scheme"
  end

  test "dala.link exits non-zero on invalid input" do
    Process.flag(:trap_exit, true)

    try do
      Mix.Tasks.Dala.Link.run(["nope"])
      flunk("expected exit")
    catch
      :exit, {:shutdown, 1} -> :ok
    after
      Process.flag(:trap_exit, false)
    end
  end

  test "dala.link warns when the device filter matches nothing" do
    out =
      capture_io(fn ->
        Mix.Tasks.Dala.Link.run(["https://example.com", "--device", @bogus_device])
      end)

    assert out =~ "No devices found."
  end

  describe "Dala.Link.report/1" do
    test "renders success and failure lines per device" do
      out =
        capture_io(fn ->
          Mix.Tasks.Dala.Link.report([
            {"Pixel", {:ok, "opened myapp://x"}},
            {"Sim", {:error, "openurl failed"}}
          ])
        end)

      assert out =~ "Pixel: opened myapp://x"
      assert out =~ "Sim: openurl failed"
    end

    test "empty results warn" do
      out = capture_io(fn -> Mix.Tasks.Dala.Link.report([]) end)
      assert out =~ "No devices found."
    end
  end

  test "dala.link requires exactly one positional URL" do
    assert_raise Mix.Error, ~r/Usage: mix dala.link/, fn ->
      capture_io(fn -> Mix.Tasks.Dala.Link.run([]) end)
    end
  end

  # ── dala.location ───────────────────────────────────────────────────────────

  test "dala.location validates coordinates before dispatch" do
    out =
      capture_io(fn ->
        Mix.Tasks.Dala.Location.run(["set", "91,10"])
      end)

    assert out =~ "±90"
  end

  test "dala.location set/reset surface resolution errors" do
    for args <- [["set", "21.0,105.8"], ["reset"]] do
      out =
        capture_io(fn ->
          Mix.Tasks.Dala.Location.run(args ++ ["--device", @bogus_device])
        end)

      assert out =~ ~s(no device matched)
      assert out =~ "mix dala.devices"
    end
  end

  test "dala.location requires set/reset with coordinates" do
    assert_raise Mix.Error, ~r/Usage: mix dala.location/, fn ->
      capture_io(fn -> Mix.Tasks.Dala.Location.run([]) end)
    end

    assert_raise Mix.Error, ~r/Usage: mix dala.location/, fn ->
      capture_io(fn -> Mix.Tasks.Dala.Location.run(["set"]) end)
    end
  end

  # ── dala.reset ──────────────────────────────────────────────────────────────

  test "dala.reset with a non-matching filter touches nothing and warns" do
    out =
      capture_io(fn ->
        Mix.Tasks.Dala.Reset.run(["--device", @bogus_device])
      end)

    assert out =~ "No devices found."
    assert out =~ "mix dala.devices"
  end

  test "dala.reset --json reports an empty result list" do
    out =
      capture_io(fn ->
        Mix.Tasks.Dala.Reset.run(["--device", @bogus_device, "--json"])
      end)

    assert {:ok, %{"results" => []}} = decode_json_line(out)
  end

  # ── dala.screen baselines ───────────────────────────────────────────────────

  test "dala.screen with no mode shows usage including baseline flags" do
    out = capture_io(fn -> Mix.Tasks.Dala.Screen.run([]) end)
    assert out =~ "--baseline"
    assert out =~ "--compare"
  end

  # Baseline errors go through DalaDev.Output.error → Mix.shell().info → stdout.
  test "dala.screen baseline save surfaces unknown devices" do
    out =
      capture_io(:stdio, fn ->
        Mix.Tasks.Dala.Screen.run([
          "--baseline",
          "home",
          "--node",
          @bogus_device
        ])
      end)

    assert out =~ "Failed to save baseline"
  end

  test "dala.screen baseline compare surfaces unknown devices" do
    out =
      capture_io(:stdio, fn ->
        Mix.Tasks.Dala.Screen.run([
          "--compare",
          "home",
          "--node",
          @bogus_device
        ])
      end)

    assert out =~ "Failed to compare"
  end

  # ── dala.emulators recipes ──────────────────────────────────────────────────

  test "dala.emulators --start requires an id" do
    assert_raise Mix.Error, ~r/--start requires --id/, fn ->
      capture_io(fn -> Mix.Tasks.Dala.Emulators.run(["--start"]) end)
    end
  end

  test "dala.emulators rejects unknown recipes before resolving devices" do
    assert_raise Mix.Error, ~r/Unknown recipe "bogus-recipe"/, fn ->
      capture_io(fn ->
        Mix.Tasks.Dala.Emulators.run([
          "--start",
          "--id",
          "whatever",
          "--recipe",
          "bogus-recipe"
        ])
      end)
    end
  end

  test "dala.emulators --list still renders sections" do
    out = capture_io(fn -> Mix.Tasks.Dala.Emulators.run(["--list", "--android"]) end)
    assert out =~ "Android emulators"
  end

  # ── extracted task seams ────────────────────────────────────────────────────

  describe "Dala.Port.report/2" do
    @entry %{
      device: "Pixel",
      id: "5554",
      kind: :dist,
      port: 9100,
      node: :"app_android_5554@127.0.0.1",
      pids: []
    }

    @listening %{@entry | pids: [123]}

    test "table shows free and listening rows plus a kill hint" do
      out =
        capture_io(fn ->
          Mix.Tasks.Dala.Port.report([@entry, @listening], [])
        end)

      assert out =~ "Pixel"
      assert out =~ "9100"
      assert out =~ "free"
      assert out =~ "pid 123"
      assert out =~ "--kill"
    end

    test "json emits entries with listening pids" do
      out =
        capture_io(fn ->
          Mix.Tasks.Dala.Port.report([@listening], json: true)
        end)

      assert {:ok, %{"ports" => [port]}} = decode_json_line(out)
      assert port["device"] == "Pixel"
      assert port["kind"] == "dist"
      assert port["listening_pids"] == [123]
    end

    test "kill with nothing to kill reports it" do
      out = capture_io(fn -> Mix.Tasks.Dala.Port.report([@entry], kill: true) end)
      assert out =~ "Nothing to kill"
    end

    test "empty entries warn regardless of mode" do
      for opts <- [[], [json: true]] do
        out = capture_io(fn -> Mix.Tasks.Dala.Port.report([], opts) end)
        assert out =~ "No devices connected"
      end
    end
  end

  describe "Dala.Shell.handle_plan/4" do
    test ":shell prints the copy-paste command" do
      out =
        capture_io(:stdio, fn ->
          Mix.Tasks.Dala.Shell.handle_plan(
            {:shell, "adb -s s shell run-as com.a"},
            "Pixel",
            "com.a",
            false
          )
        end)

      assert out =~ "run-as com.a"
      assert out =~ "--exec"
    end

    test ":dir prints the container command with a hint" do
      out =
        capture_io(:stdio, fn ->
          Mix.Tasks.Dala.Shell.handle_plan(
            {:dir, "xcrun simctl get_app_container U com.a data"},
            "iPhone",
            "com.a",
            false
          )
        end)

      assert out =~ "get_app_container"
      assert out =~ "container path"
    end

    test ":exec runs the plan and reports non-zero status" do
      {_result, out} =
        with_io(fn ->
          Mix.Tasks.Dala.Shell.handle_plan({:exec, "true"}, "Pixel", "com.a", true)
        end)

      assert out =~ "Running in Pixel"
      refute out =~ "exited with status"

      {_result, out2} =
        with_io(fn ->
          Mix.Tasks.Dala.Shell.handle_plan({:exec, "exit 3"}, "Pixel", "com.a", true)
        end)

      assert out2 =~ "exited with status 3"
    end

    test ":unsupported explains the limitation" do
      out =
        capture_io(:stdio, fn ->
          Mix.Tasks.Dala.Shell.handle_plan(:unsupported, "iPhone", "com.a", false)
        end)

      assert out =~ "physical iOS"
      assert out =~ "pull_file"
    end
  end

  describe "Dala.Reset.report/2" do
    test "success and failure lines per device" do
      out =
        capture_io(fn ->
          Mix.Tasks.Dala.Reset.report(
            [{"Pixel", {:ok, "stopped"}}, {"Sim", {:error, "boom"}}],
            false
          )
        end)

      assert out =~ "Pixel: stopped"
      assert out =~ "Sim: boom"
    end

    test "json encodes ok/error outcomes" do
      out =
        capture_io(fn ->
          Mix.Tasks.Dala.Reset.report(
            [{"Pixel", {:ok, "stopped"}}, {"Sim", {:error, "boom"}}],
            true
          )
        end)

      assert {:ok, %{"results" => results}} = decode_json_line(out)
      assert %{"device" => "Pixel", "ok" => true} = Enum.find(results, & &1["ok"])
      assert %{"device" => "Sim", "error" => "boom"} = Enum.find(results, &(!&1["ok"]))
    end

    test "empty result list warns with a hint" do
      out = capture_io(fn -> Mix.Tasks.Dala.Reset.report([], true) end)
      assert out =~ "No devices found."
    end
  end
end
