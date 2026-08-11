defmodule Soundboard.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias Soundboard.Discord.RuntimeCapability
  alias Soundboard.YouTube.YtDlp
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Soundboard Application")

    children = [
      Soundboard.Repo,
      {Task.Supervisor, name: Soundboard.AudioTaskSupervisor},
      {Soundboard.AudioPlayer, []},
      {Soundboard.VideoPlayer, []},
      SoundboardWeb.Telemetry,
      {Phoenix.PubSub, name: Soundboard.PubSub},
      SoundboardWeb.Presence,
      SoundboardWeb.PresenceHandler,
      Soundboard.Discord.Handler.State,
      SoundboardWeb.Endpoint
      | discord_children()
    ]

    opts = [strategy: :one_for_one, name: Soundboard.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      _ =
        Task.Supervisor.start_child(Soundboard.AudioTaskSupervisor, fn ->
          ensure_ytdlp()
        end)

      {:ok, pid}
    end
  end

  defp ensure_ytdlp do
    case YtDlp.ensure() do
      {:ok, path} ->
        Logger.info("yt-dlp executable: #{path}")
        ensure_ytdlp_js_runtime()

      {:error, reason} ->
        Logger.warning("yt-dlp unavailable: #{reason}. YouTube video playback will be disabled.")
    end
  end

  defp ensure_ytdlp_js_runtime do
    case YtDlp.resolve_js_runtime() do
      {runtime, path} ->
        Logger.info("yt-dlp JS runtime: #{runtime} (#{path})")

      nil ->
        Logger.warning(
          "No JS runtime found for yt-dlp (install nodejs 22+). YouTube may only return storyboard images until one is available."
        )
    end
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
