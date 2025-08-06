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

    # Start Nostrum application manually after runtime config is loaded
    if Application.get_env(:soundboard, :env) != :test do
      Logger.info("Starting Nostrum application...")
      Application.ensure_all_started(:nostrum)
    end

    # Initialize presence handler state
    PresenceHandler.init()

    # Base children that always start
    base_children = [
      SoundboardWeb.Telemetry,
      {Phoenix.PubSub, name: Soundboard.PubSub},
      SoundboardWeb.Presence,
      SoundboardWeb.Endpoint,
      {SoundboardWeb.AudioPlayer, []},
      Soundboard.Repo,
      SoundboardWeb.DiscordHandler.State
    ]

    # Add Discord consumer only in non-test environments
    children =
      if Application.get_env(:soundboard, :env) != :test do
        # Add the Discord consumer directly as a supervised child
        base_children ++ [SoundboardWeb.DiscordHandler]
      else
        base_children
      end

    opts = [strategy: :one_for_one, name: Soundboard.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SoundboardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
