defmodule DalaDev.OtpDownloaderValidTest do
  use ExUnit.Case, async: true

  alias DalaDev.OtpDownloader

  defp with_tmp_dir(fun) do
    dir = Path.join(System.tmp_dir!(), "dala_otp_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      fun.(dir)
    after
      File.rm_rf(dir)
    end
  end

  defp touch_epmd_sources(dir, files) do
    Enum.each(files, fn f ->
      path = Path.join([dir, "erts", "epmd", "src", f])
      File.mkdir_p!(Path.dirname(path))
      File.touch!(path)
    end)
  end

  describe "valid_otp_dir?/2" do
    test "invalid when dir does not exist" do
      refute OtpDownloader.valid_otp_dir?(
               Path.join(System.tmp_dir!(), "dala_missing_#{:erlang.unique_integer()}"),
               "otp-android-x"
             )
    end

    test "invalid when dir exists but has no erts-* subdir" do
      with_tmp_dir(fn dir ->
        refute OtpDownloader.valid_otp_dir?(dir, "otp-android-x")
      end)
    end

    test "valid for android when erts-* present" do
      with_tmp_dir(fn dir ->
        File.mkdir_p!(Path.join(dir, "erts-15.2"))
        assert OtpDownloader.valid_otp_dir?(dir, "otp-android-73ba6e0f")
      end)
    end

    test "valid for ios-sim when erts-* present" do
      with_tmp_dir(fn dir ->
        File.mkdir_p!(Path.join(dir, "erts-15.2"))
        assert OtpDownloader.valid_otp_dir?(dir, "otp-ios-sim-73ba6e0f")
      end)
    end

    test "ios-device requires EPMD sources even with erts-*" do
      with_tmp_dir(fn dir ->
        File.mkdir_p!(Path.join(dir, "erts-15.2"))

        # Missing epmd extras → invalid despite valid base layout
        refute OtpDownloader.valid_otp_dir?(dir, "otp-ios-device-73ba6e0f")

        # Add all required files → valid
        touch_epmd_sources(dir, ~w[epmd.c epmd_srv.c epmd_cli.c epmd.h epmd_int.h])

        assert OtpDownloader.valid_otp_dir?(dir, "otp-ios-device-73ba6e0f")
      end)
    end

    test "ios-device missing a single header is invalid" do
      with_tmp_dir(fn dir ->
        File.mkdir_p!(Path.join(dir, "erts-15.2"))

        touch_epmd_sources(dir, ~w[epmd.c epmd_srv.c epmd_cli.c epmd_int.h])

        refute OtpDownloader.valid_otp_dir?(dir, "otp-ios-device-73ba6e0f")
      end)
    end
  end

  describe "ios_device_extras_present?/1" do
    test "false on empty dir" do
      with_tmp_dir(fn dir ->
        refute OtpDownloader.ios_device_extras_present?(dir)
      end)
    end

    test "true when all five files exist" do
      with_tmp_dir(fn dir ->
        touch_epmd_sources(dir, ~w[epmd.c epmd_srv.c epmd_cli.c epmd.h epmd_int.h])

        assert OtpDownloader.ios_device_extras_present?(dir)
      end)
    end
  end

  describe "otp dir path helpers" do
    test "android_otp_dir/1 defaults to arm64 name" do
      path = OtpDownloader.android_otp_dir()
      assert String.contains?(path, "otp-android-73ba6e0f")
    end

    test "android_otp_dir/1 maps armeabi-v7a to arm32 name" do
      path = OtpDownloader.android_otp_dir("armeabi-v7a")
      assert String.contains?(path, "otp-android-arm32-73ba6e0f")
    end

    test "ios_sim_otp_dir/0 and ios_device_otp_dir/0 include hash" do
      assert String.contains?(OtpDownloader.ios_sim_otp_dir(), "otp-ios-sim-73ba6e0f")
      assert String.contains?(OtpDownloader.ios_device_otp_dir(), "otp-ios-device-73ba6e0f")
    end
  end
end
