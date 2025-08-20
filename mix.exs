defmodule Soundboard.MixProject do
  use Mix.Project

  def project do
    [
      app: :soundboard,
      version: "1.3.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [
        tool: ExCoveralls,
        ignore_modules: [
          SoundboardWeb.CoreComponents,
          SoundboardWeb.Components.FlashComponent,
          SoundboardWeb.Components.Layouts,
          SoundboardWeb.Router,
          SoundboardWeb.Telemetry,
          SoundboardWeb.Endpoint,
          SoundboardWeb.Gettext,
          # Controllers and views with no meaningful coverage needs
          SoundboardWeb.ErrorHTML,
          SoundboardWeb.ErrorJSON,
          SoundboardWeb.PageController,
          SoundboardWeb.PageHTML,
          SoundboardWeb.UploadController,
          # Live views that might need separate testing strategy
          SoundboardWeb.FavoritesLive,
          SoundboardWeb.PresenceLive,
          SoundboardWeb.Presence,
          # Repo and application modules
          Soundboard.Repo,
          # Test support files
          SoundboardWeb.ConnCase,
          Soundboard.DataCase,
          Soundboard.TestHelpers
        ]
      ],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.github": :test
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    apps = [:logger, :runtime_tools]

    # Don't auto-start nostrum - let it start after runtime config loads

    [
      mod: {Soundboard.Application, []},
      extra_applications: apps,
      included_applications: if(Mix.env() == :test, do: [:nostrum], else: [])
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.18"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons, github: "tailwindlabs/heroicons", tag: "v2.1.1", app: false},
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},
      {:nostrum, github: "Kraigie/nostrum", branch: "master"},
      {:ecto_sqlite3, "~> 0.18.0"},
      {:number, "~> 1.0"},
      {:ueberauth, "~> 0.10.5"},
      {:ueberauth_discord, "~> 0.6"},
      {:plug_cowboy, "~> 2.6"},
      {:httpoison, "~> 2.0"},
      {:mock, "~> 0.3.9", only: :test},
      {:excoveralls, "~> 0.18.5", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind soundboard", "esbuild soundboard"],
      "assets.deploy": [
        "tailwind soundboard --minify",
        "esbuild soundboard --minify",
        "phx.digest"
      ]
    ]
  end
end
