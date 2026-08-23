defmodule DalaDev.LocationSpoofTest do
  use ExUnit.Case, async: true

  alias DalaDev.LocationSpoof

  describe "parse_coords/1" do
    test "parses comma and space separated coordinates" do
      assert {:ok, 21.0, 105.83} == LocationSpoof.parse_coords("21.0,105.83")
      assert {:ok, -33.9, 151.2} == LocationSpoof.parse_coords("-33.9 151.2")
    end

    test "rejects malformed input" do
      assert {:error, _} = LocationSpoof.parse_coords("abc")
      assert {:error, _} = LocationSpoof.parse_coords("1.0")
      assert {:error, _} = LocationSpoof.parse_coords("1.0,2.0,3.0")
      assert {:error, _} = LocationSpoof.parse_coords(nil)
    end

    test "validates ranges" do
      assert {:error, reason} = LocationSpoof.parse_coords("91.0,10.0")
      assert reason =~ "±90"
      assert {:error, _} = LocationSpoof.parse_coords("10.0,181.0")
      assert {:ok, _, _} = LocationSpoof.parse_coords("90,180")
      assert {:ok, _, _} = LocationSpoof.parse_coords("-90,-180")
    end
  end

  describe "command builders" do
    # adb's geo fix takes LONGITUDE first — the classic footgun.
    test "android_set_command/3 puts longitude before latitude" do
      assert LocationSpoof.android_set_command("emulator-5554", 21.0, 105.5) == [
               "-s",
               "emulator-5554",
               "emu",
               "geo",
               "fix",
               "105.5",
               "21.0"
             ]
    end

    test "ios_set_command/3 keeps lat,lng order" do
      assert LocationSpoof.ios_set_command("UDID", 21.0, 105.5) == [
               "simctl",
               "location",
               "UDID",
               "set",
               "21.0,105.5"
             ]
    end

    test "ios_clear_command/1" do
      assert LocationSpoof.ios_clear_command("UDID") == ["simctl", "location", "UDID", "clear"]
    end
  end

  @emulator %DalaDev.Device{
    platform: :android,
    serial: "emulator-5554",
    type: :emulator,
    name: "Pixel"
  }
  @phone %DalaDev.Device{platform: :android, serial: "SERIAL1", type: :physical}
  @sim %DalaDev.Device{platform: :ios, serial: "AAAACCCC-DDDD", type: :simulator, name: "iPhone"}
  @phys %DalaDev.Device{platform: :ios, serial: "PHYSDUDID", type: :physical}

  describe "set/4 dispatch arms" do
    test "emulator success passes longitude before latitude" do
      {:ok, msg} =
        LocationSpoof.set(21.0, 105.5, nil,
          devices: [@emulator],
          exec: fn cmd ->
            send(self(), {:cmd, cmd})
            {:ok, ""}
          end
        )

      assert msg =~ "Pixel → 21.0,105.5"

      assert_received {:cmd,
                       {:adb, ["-s", "emulator-5554", "emu", "geo", "fix", "105.5", "21.0"]}}
    end

    test "emulator adb failure" do
      assert {:error, reason} =
               LocationSpoof.set(1.0, 2.0, nil,
                 devices: [@emulator],
                 exec: fn _ -> {:error, :timeout} end
               )

      assert reason =~ "geo fix failed"
    end

    test "physical android rejected" do
      assert {:error, reason} =
               LocationSpoof.set(1.0, 2.0, nil, devices: [@phone], exec: fn _ -> {:ok, ""} end)

      assert reason =~ "emulators only"
    end

    test "simulator success and simctl failure" do
      assert {:ok, msg} =
               LocationSpoof.set(-33.9, 151.2, nil, devices: [@sim], exec: fn _ -> {:ok, ""} end)

      assert msg =~ "iPhone → -33.9,151.2"

      assert {:error, reason} =
               LocationSpoof.set(1.0, 2.0, nil,
                 devices: [@sim],
                 exec: fn _ -> {:error, "err out"} end
               )

      assert reason =~ "simctl location failed: err out"
    end

    test "physical ios rejected; resolution errors pass through" do
      assert {:error, reason} =
               LocationSpoof.set(1.0, 2.0, nil, devices: [@phys], exec: fn _ -> {:ok, ""} end)

      assert reason =~ "physical iOS"

      assert {:error, reason} =
               LocationSpoof.set(1.0, 2.0, nil, devices: [], exec: fn _ -> flunk() end)

      assert reason =~ "no connected devices"

      assert {:error, reason} =
               LocationSpoof.set(1.0, 2.0, "zzz", devices: [@sim], exec: fn _ -> flunk() end)

      assert reason =~ ~s(no device matched "zzz")
    end
  end

  describe "default executor (no :exec opt)" do
    test "adb geo fix failure on a bogus emulator is structured" do
      assert {:error, reason} =
               LocationSpoof.set(1.0, 2.0, nil,
                 devices: [
                   %DalaDev.Device{platform: :android, serial: "BOGUS_EMU", type: :emulator}
                 ]
               )

      assert reason =~ "geo fix failed"
    end

    test "simctl failure on a bogus udid is structured" do
      assert {:error, reason} =
               LocationSpoof.clear(nil,
                 devices: [
                   %DalaDev.Device{
                     platform: :ios,
                     serial: "11111111-2222-3333-4444-555555555555",
                     type: :simulator
                   }
                 ]
               )

      assert reason =~ "simctl location clear failed"
    end
  end

  describe "clear/2 dispatch arms" do
    test "simulator success and failure" do
      assert {:ok, "location spoof cleared"} =
               LocationSpoof.clear(nil, devices: [@sim], exec: fn _ -> {:ok, ""} end)

      assert {:error, reason} =
               LocationSpoof.clear(nil, devices: [@sim], exec: fn _ -> {:error, "boom"} end)

      assert reason =~ "simctl location clear failed: boom"
    end

    test "non-simulator devices rejected" do
      for device <- [@emulator, @phys] do
        assert {:error, reason} =
                 LocationSpoof.clear(nil, devices: [device], exec: fn _ -> flunk("never") end)

        assert reason =~ "iOS-Simulator-only"
      end
    end
  end
end
