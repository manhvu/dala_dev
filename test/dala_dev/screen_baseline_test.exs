defmodule DalaDev.ScreenBaselineTest do
  use ExUnit.Case, async: false

  alias DalaDev.ScreenBaseline

  @device %DalaDev.Device{platform: :ios, type: :simulator, serial: "AAAABBBB-CCCC"}

  describe "path helpers" do
    test "baseline_path/2 sanitizes device id and name" do
      path = ScreenBaseline.baseline_path("emulator-5554", "home screen")
      assert path == ".dala/screenshots/emulator-5554/home_screen.png"
    end

    test "diff_path/2 uses the .new.png suffix" do
      assert ScreenBaseline.diff_path("UDID", "home") == ".dala/screenshots/UDID/home.new.png"
    end

    test "unsafe characters are replaced" do
      path = ScreenBaseline.baseline_path("../evil", "a/b")
      refute path =~ ".."
      assert path =~ "_evil"
    end
  end

  describe "compare_bytes/2" do
    test "identical bytes match" do
      assert ScreenBaseline.compare_bytes(<<1, 2, 3>>, <<1, 2, 3>>) == :match
    end

    test "different bytes report both sizes" do
      assert {:changed, size_a, size_b} =
               ScreenBaseline.compare_bytes(<<0::size(8 * 100)>>, <<0::size(8 * 200)>>)

      assert size_a == 100
      assert size_b == 200
    end
  end

  describe "compare/2" do
    test "returns :no_baseline when nothing was saved for the device" do
      assert {:error, :no_baseline} = ScreenBaseline.compare(@device, "no_such_baseline_xyz")
    end
  end

  # display_id/1 of the @device serial is its first 8 hex chars, lowercased
  @device_id "aaaabbbb"
  @device_dir ".dala/screenshots/aaaabbbb"

  setup do
    File.rm_rf(@device_dir)
    on_exit(fn -> File.rm_rf(@device_dir) end)
    :ok
  end

  # Capture stub: pretends ScreenCapture captured the given bytes.
  defp capture_writing(bytes) do
    fn _ref, save_as: path ->
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes)
      {:ok, path}
    end
  end

  defp capture_returning(bytes), do: fn _ref, [] -> {:ok, bytes} end

  describe "save/3 with injected capture" do
    test "stores the captured bytes at the baseline path" do
      assert {:ok, path} =
               ScreenBaseline.save(@device, "home", capture: capture_writing(<<1, 2, 3>>))

      assert path == ScreenBaseline.baseline_path(@device_id, "home")
      assert File.read!(path) == <<1, 2, 3>>
    end

    test "capture errors pass through" do
      assert {:error, :boom} =
               ScreenBaseline.save(@device, "home", capture: fn _r, _o -> {:error, :boom} end)
    end

    test "unknown device refs are rejected" do
      assert {:error, :device_not_found} =
               ScreenBaseline.save("NOT_A_DEVICE_XYZ", "home",
                 capture: fn _r, _o -> flunk("never") end
               )
    end
  end

  describe "compare/3 with injected capture" do
    test "matching bytes report :match and write no diff file" do
      {:ok, _} = ScreenBaseline.save(@device, "home", capture: capture_writing("same"))

      assert {:ok, :match} =
               ScreenBaseline.compare(@device, "home", capture: capture_returning("same"))

      refute File.exists?(ScreenBaseline.diff_path(@device_id, "home"))
    end

    test "changed bytes save a .new.png and report sizes" do
      {:ok, _} = ScreenBaseline.save(@device, "home", capture: capture_writing("old-bytes"))

      assert {:ok, {:changed, details}} =
               ScreenBaseline.compare(@device, "home", capture: capture_returning("new-bytes!!"))

      assert details.size_a == byte_size("old-bytes")
      assert details.size_b == byte_size("new-bytes!!")
      assert File.read!(details.current) == "new-bytes!!"
      assert details.baseline == ScreenBaseline.baseline_path(@device_id, "home")
    end

    test "capture errors pass through" do
      {:ok, _} = ScreenBaseline.save(@device, "home", capture: capture_writing("x"))

      assert {:error, :camera_broke} =
               ScreenBaseline.compare(@device, "home",
                 capture: fn _r, _o -> {:error, :camera_broke} end
               )
    end
  end
end
