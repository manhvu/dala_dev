defmodule DalaDev.MixProject do
  use Mix.Project

  def project do
    [
      app: :dala_dev,
      version: "0.4.0",
      elixir: "~> 1.18",
      description: "Development tooling for the Dala framework",
      source_url: "https://github.com/ohhi-vn/dala_dev",
      deps: deps(),
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls, output: "cover"]
    ]
  end

  def application do
    [mod: {DalaDev.Application, []}, extra_applications: [:logger]]
  end

  defp deps do
    [
      {:eqrcode, "~> 0.2"},
      {:ex_ratatui, "~> 0.11"},
      {:avatarz, "~> 0.2", optional: true},
      {:image, "~> 0.54", optional: true},
      # Dev server — optional so CLI-only users don't pull the Phoenix stack.
      # `mix dala.server` / `mix dala.web` check availability and print a hint
      # when these are missing.
      {:phoenix_live_view, "~> 1.1", optional: true},
      {:bandit, "~> 1.11", optional: true},
      {:phoenix_pubsub, "~> 2.0", optional: true},
      {:plug_crypto, "~> 2.0", optional: true},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:jump_credo_checks, "~> 0.1.0", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:lazy_html, ">= 0.1.0", only: :test, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/logo/Dala_logo_512.png",
      source_url: "https://github.com/ohhi-vn/dala_dev",
      source_url_pattern: "https://github.com/ohhi-vn/dala_dev/blob/main/%{path}#L%{line}",
      extras: [
        "README.md": [title: "dala_dev"],
        "guides/beginner_guide.md": [title: "Beginner Step-by-Step Guide"],
        "guides/development_workflow.md": [title: "Development Workflow"],
        "guides/release_and_packaging.md": [title: "Release and Packaging"],
        "guides/architecture.md": [title: "Architecture"],
        "guides/dala_commands.md": [title: "Dala Commands"],
        "guides/tui.md": [title: "Terminal UI (TUI)"]
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        "Mix Tasks": ~r/Mix\.Tasks\./,
        Server: ~r/DalaDev\.Server/,
        TUI: ~r/DalaDev\.Tui/,
        Internals: ~r/DalaDev/
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT", "MPL-2.0"],
      links: %{"GitHub" => "https://github.com/ohhi-vn/dala_dev"}
    ]
  end
end
