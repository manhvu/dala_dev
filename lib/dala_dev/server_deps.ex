defmodule DalaDev.ServerDeps do
  @moduledoc """
  Guards for the optional Phoenix dev-server dependencies.

  `phoenix_live_view` and `bandit` are optional dependencies. Tasks that need
  them (`mix dala.server`, `mix dala.web`) call `ensure_available!/0` to fail
  with an actionable message instead of a cryptic module-not-found error.
  """

  @doc "Raises with an install hint if the dev-server deps are not available."
  @spec ensure_available!() :: :ok
  def ensure_available! do
    if available?() do
      :ok
    else
      Mix.raise("""
      The dala_dev dev server requires optional dependencies that are not installed.

      Add to your mix.exs:

          {:phoenix_live_view, "~> 1.1"},
          {:bandit, "~> 1.11"},

      then run `mix deps.get` and retry.
      """)
    end
  end

  @doc "Returns true if the Phoenix dev-server dependencies are loadable."
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(Phoenix.LiveView) and Code.ensure_loaded?(Bandit)
  end
end
