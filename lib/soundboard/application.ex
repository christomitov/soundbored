defmodule Soundboard.Application do
  @moduledoc false

  use Application
  alias Soundboard.Discord.RuntimeCapability
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Soundboard Application")

    Application.put_env(:soundboard, :bot_ready, false)

    children = [
      Soundboard.Repo,
      {Task.Supervisor, name: Soundboard.AudioTaskSupervisor},
      {Registry, keys: :unique, name: Soundboard.AudioPlayer.Registry},
      {DynamicSupervisor, name: Soundboard.AudioPlayer.Supervisor, strategy: :one_for_one},
      SoundboardWeb.Telemetry,
      {Phoenix.PubSub, name: Soundboard.PubSub},
      SoundboardWeb.Presence,
      SoundboardWeb.PresenceHandler,
      Soundboard.Discord.Handler.State,
      SoundboardWeb.Endpoint
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

  @impl true
  def config_change(changed, _new, removed) do
    SoundboardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
