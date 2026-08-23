defmodule DalaDev.ServerDepsTest do
  use ExUnit.Case, async: true

  alias DalaDev.ServerDeps

  describe "available?/0" do
    test "returns true when the Phoenix deps are loadable" do
      # In the dev/test environment Phoenix + Bandit are installed
      assert ServerDeps.available?() == true
    end
  end

  describe "ensure_available!/0" do
    test "returns :ok when deps are available" do
      # In the dev/test environment the Phoenix deps are installed
      assert ServerDeps.ensure_available!() == :ok
    end
  end
end
