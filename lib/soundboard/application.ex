defmodule Soundboard.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias SoundboardWeb.Live.PresenceHandler
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Soundboard Application")

    # Initialize presence handler state
    PresenceHandler.init()

    case Application.ensure_all_started(:nostrum) do
      {:ok, started_apps} ->
        Logger.info("Started Nostrum and dependencies: #{inspect(started_apps)}")

        children = [
          SoundboardWeb.Telemetry,
          {Phoenix.PubSub, name: Soundboard.PubSub},
          SoundboardWeb.Presence,
          SoundboardWeb.Endpoint,
          {SoundboardWeb.AudioPlayer, []},
          Soundboard.Repo,
          SoundboardWeb.DiscordHandler.State,
          SoundboardWeb.DiscordHandler
        ]

        opts = [strategy: :one_for_one, name: Soundboard.Supervisor]
        Supervisor.start_link(children, opts)

      {:error, {app, reason}} ->
        Logger.error("Failed to start Nostrum dependency #{app}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SoundboardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
