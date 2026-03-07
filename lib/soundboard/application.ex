defmodule Soundboard.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias Soundboard.Discord.RuntimeCapability
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Soundboard Application")

    children = [
      SoundboardWeb.Telemetry,
      {Phoenix.PubSub, name: Soundboard.PubSub},
      SoundboardWeb.Presence,
      SoundboardWeb.PresenceHandler,
      SoundboardWeb.Endpoint,
      {Soundboard.AudioPlayer, []},
      Soundboard.Repo,
      Soundboard.Discord.Handler.State
      | discord_children()
    ]

    opts = [strategy: :one_for_one, name: Soundboard.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp discord_children do
    if RuntimeCapability.discord_handler_enabled?() do
      [Soundboard.Discord.Handler]
    else
      RuntimeCapability.log_degraded_mode()
      []
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
