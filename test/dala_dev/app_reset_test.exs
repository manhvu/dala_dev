defmodule DalaDev.AppResetTest do
  use ExUnit.Case, async: true

  alias DalaDev.{AppReset, Device}

  describe "android_packages/1" do
    test "includes the bundle id and the com.dala wrapper package" do
      packages = AppReset.android_packages(bundle_id: "com.example.myapp", app_name: "my_app")

      assert packages == ["com.example.myapp", "com.dala.my_app"]
    end

    test "deduplicates when the bundle id is already the wrapper form" do
      packages = AppReset.android_packages(bundle_id: "com.dala.my_app", app_name: "my_app")

      assert packages == ["com.dala.my_app"]
    end

    test "falls back to Config.bundle_id when not overridden" do
      packages = AppReset.android_packages(app_name: "some_app")
      assert hd(packages) == DalaDev.Config.bundle_id()
    end
  end

  describe "android_stop_commands/2" do
    test "force-stops every package and clears logcat last" do
      cmds = AppReset.android_stop_commands("emulator-5554", ["com.a.b", "com.dala.b"])

      assert [
               ["-s", "emulator-5554", "shell", "am", "force-stop", "com.a.b"],
               ["-s", "emulator-5554", "shell", "am", "force-stop", "com.dala.b"],
               ["-s", "emulator-5554", "logcat", "-c"]
             ] == cmds
    end
  end

  describe "android_clear_data_commands/2" do
    test "runs pm clear per package" do
      cmds = AppReset.android_clear_data_commands("serial-1", ["com.a.b"])

      assert cmds == [["-s", "serial-1", "shell", "pm", "clear", "com.a.b"]]
    end
  end

  describe "ios_sim_commands/3" do
    test "terminates both wrapper and project bundle without data wipe" do
      cmds = AppReset.ios_sim_commands("UDID123", "com.example.app", false)
      args = Enum.map(cmds, fn {a, _} -> a end)

      assert args == [
               ["simctl", "terminate", "UDID123", "com.example.app"],
               [
                 "simctl",
                 "terminate",
                 "UDID123",
                 "com.dala." <> to_string(Mix.Project.config()[:app])
               ]
             ]
    end

    test "adds uninstall when clear_data is requested" do
      cmds = AppReset.ios_sim_commands("UDID123", "com.example.app", true)

      assert {["simctl", "uninstall", "UDID123", "com.example.app"], true} in cmds
    end
  end

  describe "reset/2 android via exec seam" do
    @android %Device{platform: :android, serial: "emulator-5554", type: :emulator, name: "Pixel"}

    test "ok path summarizes stopped packages" do
      {:ok, msg} =
        AppReset.reset(@android,
          bundle_id: "com.example.app",
          exec: fn {:adb, _args} -> {:ok, ""} end
        )

      assert msg =~ "com.example.app"
      assert msg =~ "com.dala."
    end

    test "clear_data adds pm clear commands to the executed set" do
      {:ok, msg} =
        AppReset.reset(@android,
          bundle_id: "com.example.app",
          clear_data: true,
          exec: fn {:adb, args} ->
            send(self(), {:args, args})
            {:ok, ""}
          end
        )

      assert msg =~ "stopped"

      pm_clears =
        received(:args)
        |> Enum.count(&("pm" in &1 and "clear" in &1))

      assert pm_clears == 2
    end

    test "counts failed commands in the error" do
      stub = fn
        {:adb, ["-s", _serial, "logcat" | _]} -> {:ok, ""}
        {:adb, _} -> {:error, "device offline"}
      end

      assert {:error, reason} =
               AppReset.reset(@android, bundle_id: "com.example.app", exec: stub)

      assert reason =~ "2 of 3 adb command(s) failed"
    end
  end

  describe "reset/2 ios simulator via exec seam" do
    @sim %Device{platform: :ios, serial: "UDID123", type: :simulator, name: "iPhone 17"}

    test "ok path terminates without uninstalling by default" do
      {:ok, msg} =
        AppReset.reset(@sim,
          bundle_id: "com.example.app",
          exec: fn {:xcrun, args} ->
            send(self(), {:cmd, args})
            {:ok, ""}
          end
        )

      assert msg == "terminated com.example.app"

      # terminate project bundle + wrapper; no uninstall without clear_data
      cmds = received(:cmd)
      assert length(cmds) == 2
      refute Enum.any?(cmds, &("uninstall" in &1))
    end

    test "clear_data uninstalls and says so" do
      {:ok, msg} =
        AppReset.reset(fake_ios_sim(),
          bundle_id: "com.example.app",
          clear_data: true,
          exec: fn {:xcrun, _args} -> {:ok, ""} end
        )

      assert msg == "terminated com.example.app + uninstalled"
    end

    test "failing terminate reports the failure count" do
      assert {:error, reason} =
               AppReset.reset(@sim,
                 bundle_id: "com.example.app",
                 exec: fn {:xcrun, _args} -> {:error, "not found"} end
               )

      assert reason == "2 simctl command(s) failed"
    end
  end

  describe "reset/2 physical iOS" do
    test "reports unsupported clearly" do
      device = %Device{platform: :ios, serial: "UDID", type: :physical}

      assert {:error, msg} = AppReset.reset(device, [])
      assert msg =~ "physical"
    end
  end

  describe "reset_all/1 and reset_devices/2" do
    test "labels use device names and pass opts through" do
      devices = [
        %{fake_android() | name: "Pixel 8"},
        fake_physical_ios()
      ]

      results =
        AppReset.reset_devices(devices,
          bundle_id: "com.example.app",
          exec: fn
            {:adb, _} -> {:ok, ""}
            {:xcrun, _} -> {:ok, ""}
          end
        )

      assert [{"Pixel 8", {:ok, _}}, {"UDID-PHYS", {:error, _}}] = results
    end

    test ":devices opt bypasses discovery and :device filters it" do
      devices = [fake_android(), fake_ios_sim()]

      results =
        AppReset.reset_all(
          devices: devices,
          device: "AAAACCCC",
          bundle_id: "com.example.app",
          exec: fn _ -> {:ok, ""} end
        )

      assert length(results) == 1
      {label, {:ok, _}} = results |> hd()
      assert label == "iPhone 17"
    end

    test "unauthorized devices are skipped" do
      unauthorized = %Device{platform: :android, serial: "nope", status: :unauthorized}

      results =
        AppReset.reset_all(devices: [unauthorized], exec: fn _ -> flunk("should not run") end)

      assert results == []
    end
  end

  describe "default executor (no :exec opt)" do
    @tag :integration
    test "bogus adb serial surfaces as command failure" do
      device = %Device{platform: :android, serial: "BOGUS_RESET_SERIAL", type: :physical}
      assert match?({:error, _}, AppReset.reset(device, bundle_id: "com.example.app"))
    end

    @tag :integration
    test "bogus simulator UDID surfaces as simctl failure" do
      device = %Device{
        platform: :ios,
        serial: "00000000-0000-0000-0000-000000000000",
        type: :simulator
      }

      assert match?({:error, _}, AppReset.reset(device, bundle_id: "com.example.app"))
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp fake_android,
    do: %Device{platform: :android, serial: "emulator-5554", type: :emulator}

  defp fake_ios_sim,
    do: %Device{platform: :ios, serial: "AAAACCCC-DDDD", type: :simulator, name: "iPhone 17"}

  defp fake_physical_ios,
    do: %Device{platform: :ios, serial: "UDID-PHYS", type: :physical}

  defp received(kind) do
    receive_loop(kind, [])
  end

  defp receive_loop(kind, acc) do
    receive do
      {^kind, msg} -> receive_loop(kind, [msg | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
