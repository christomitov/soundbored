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

    ensure_dave_runtime!()

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

    # Add Discord bot only in non-test environments
    children =
      if Application.get_env(:soundboard, :env) != :test do
        # EDA gateway runs in its own OTP application.
        # We keep the handler GenServer for app-specific state/tasks.
        base_children ++ [SoundboardWeb.DiscordHandler]
      else
        base_children
      end

    opts = [strategy: :one_for_one, name: Soundboard.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp ensure_dave_runtime! do
    if Application.get_env(:soundboard, :env) != :test and Application.get_env(:eda, :dave, false) do
      unless EDA.Voice.Dave.Native.available?() do
        raise """
        EDA DAVE is enabled, but the native library is unavailable.
        Build it in `deps/eda/native/eda_dave` with `cargo build --release`,
        then copy the built artifact to `_build/<env>/lib/eda/priv/native/eda_dave.so`.
        You can temporarily disable DAVE with `EDA_DAVE=false`.
        """
      end
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
