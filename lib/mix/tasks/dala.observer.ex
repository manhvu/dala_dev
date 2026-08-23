defmodule Mix.Tasks.Dala.Observer do
  @moduledoc """
  Start the Dala Observer web interface for remote node monitoring.

  Similar to `:observer.start()` but runs as a web interface and supports
  monitoring remote nodes via RPC.
  """

  use Mix.Task

  @default_port 4000

  @impl Mix.Task
  def run(args) do
    args = DalaDev.Utils.normalize_cli_args(args || [])
    DalaDev.Output.configure([])

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [port: :integer, node: :string, name: :string, cookie: :string],
        aliases: [p: :port, n: :node]
      )

    port = Keyword.get(opts, :port, @default_port)
    target_node = Keyword.get(opts, :node, nil)
    node_name = Keyword.get(opts, :name, nil)
    cookie = Keyword.get(opts, :cookie, :erlang.get_cookie())

    if node_name do
      {:ok, _} = Node.start(:"#{node_name}", :shortnames)
    end

    if cookie do
      Node.set_cookie(cookie |> to_string() |> String.to_atom())
    end

    if target_node do
      target = target_node |> to_string() |> String.to_atom()

      case Node.connect(target) do
        true -> DalaDev.Output.success("Connected to #{target}")
        false -> DalaDev.Output.error("Failed to connect to #{target}")
      end
    end

    DalaDev.Output.info("Starting Dala Observer on http://localhost:#{port}/observer")

    if target_node do
      DalaDev.Output.info("Initially observing: #{target_node}")
    end

    Application.put_env(:dala_dev, DalaDev.Server.Endpoint,
      http: [port: port],
      server: true,
      secret_key_base: "observe_key_base_#{:crypto.strong_rand_bytes(16) |> Base.encode64()}"
    )

    {:ok, _} = Application.ensure_all_started(:phoenix)
    {:ok, _} = Application.ensure_all_started(:phoenix_live_view)
    {:ok, _} = Application.ensure_all_started(:bandit)

    DalaDev.Server.Endpoint.start_link()

    :timer.sleep(:infinity)
  end
end
