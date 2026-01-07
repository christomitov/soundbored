defmodule Soundboard.VoiceListener.ClawdbotAPI do
  @moduledoc """
  Sends voice queries to Clawdbot.
  Clawdbot handles the response AND TTS playback via SoundBored's play-stream.
  """
  require Logger

  @clawdbot_timeout 60_000

  def process_query(query, context, _guild_id) do
    Logger.info("Processing voice query: #{query}")
    clawdbot_url = Application.get_env(:soundboard, :clawdbot_api_url)

    if is_nil(clawdbot_url) do
      Logger.warning("Clawdbot API URL not configured")
      {:error, :not_configured}
    else
      send_to_clawdbot(query, context, clawdbot_url)
    end
  end

  defp send_to_clawdbot(query, context, url) do
    prompt = build_prompt(query, context)
    token = Application.get_env(:soundboard, :clawdbot_api_token, "")

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{token}"}
    ]

    body = Jason.encode!(%{message: prompt})

    case HTTPoison.post(url, body, headers, recv_timeout: @clawdbot_timeout) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        Logger.info("Clawdbot responded successfully")
        parse_response(resp_body)

      {:ok, %{status_code: code, body: resp_body}} ->
        Logger.warning("Clawdbot API error #{code}: #{resp_body}")
        {:error, {:api_error, code}}

      {:error, reason} ->
        Logger.error("Clawdbot request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_prompt(query, context) do
    """
    Voice chat query from Discord. You are being called via SoundBored wake word detection.

    IMPORTANT: After generating your text response, you MUST also:
    1. Generate TTS audio using ElevenLabs
    2. Send it to SoundBored's play-stream endpoint to play in voice chat

    Recent conversation context:
    #{context}

    User just said: #{query}

    Respond naturally and briefly (1-3 sentences). Then play the audio.
    """
  end

  defp parse_response(body) do
    case Jason.decode(body) do
      {:ok, %{"response" => response}} -> {:ok, response}
      {:ok, %{"message" => response}} -> {:ok, response}
      {:ok, other} ->
        Logger.warning("Unexpected response format: #{inspect(other)}")
        {:error, :invalid_response}
      {:error, _} ->
        {:error, :json_decode_error}
    end
  end
end
