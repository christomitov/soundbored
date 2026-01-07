defmodule SoundboardWeb.Api.VoiceListenerController do
  @moduledoc """
  API controller for managing the voice listener.
  """
  use SoundboardWeb, :controller
  
  alias Soundboard.VoiceListener
  
  @doc """
  GET /api/voice-listener/status
  Returns the current status of the voice listener.
  """
  def status(conn, _params) do
    status = VoiceListener.get_status()
    json(conn, %{status: "ok", data: status})
  end
  
  @doc """
  POST /api/voice-listener/start
  Starts listening in the specified voice channel.
  
  Body: { "guild_id": "123", "channel_id": "456" }
  """
  def start(conn, %{"guild_id" => guild_id, "channel_id" => channel_id}) do
    guild_id = String.to_integer(guild_id)
    channel_id = String.to_integer(channel_id)
    
    case VoiceListener.start_listening(guild_id, channel_id) do
      :ok ->
        json(conn, %{status: "ok", message: "Voice listener started"})
      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{status: "error", message: inspect(reason)})
    end
  end
  
  def start(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{status: "error", message: "Missing guild_id or channel_id"})
  end
  
  @doc """
  POST /api/voice-listener/stop
  Stops the voice listener.
  """
  def stop(conn, _params) do
    VoiceListener.stop_listening()
    json(conn, %{status: "ok", message: "Voice listener stopped"})
  end
end
