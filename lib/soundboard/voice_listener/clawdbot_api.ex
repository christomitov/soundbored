defmodule Soundboard.VoiceListener.ClawdbotAPI do
  @moduledoc """
  Handles communication with Clawdbot for processing voice queries
  and plays responses via ElevenLabs TTS.
  """
  require Logger

  alias Nostrum.Voice

  @elevenlabs_api_url "https://api.elevenlabs.io/v1/text-to-speech"
  @clawdbot_timeout 60_000

  def process_query(query, context, guild_id) do
    Logger.info("Processing voice query: #{query}")
    clawdbot_url = Application.get_env(:soundboard, :clawdbot_api_url)

    if is_nil(clawdbot_url) do
      Logger.warning("Clawdbot API URL not configured")
      {:error, :not_configured}
    else
      do_process_query(query, context, guild_id, clawdbot_url)
    end
  end

  defp do_process_query(query, context, guild_id, clawdbot_url) do
    prompt = build_prompt(query, context)

    case send_to_clawdbot(prompt, clawdbot_url) do
      {:ok, response} ->
        Logger.info("Got Clawdbot response: #{String.slice(response, 0, 100)}...")
        speak_response(response, guild_id)

      {:error, reason} ->
        Logger.error("Clawdbot query failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_prompt(query, context) do
    """
    Voice chat query from Discord. Respond conversationally and briefly (1-3 sentences max).

    Recent conversation context:
    #{context}

    User just said: #{query}

    Respond naturally as Clawd.
    """
  end

  defp send_to_clawdbot(prompt, url) do
    token = Application.get_env(:soundboard, :clawdbot_api_token)
    headers = [{"Content-Type", "application/json"}, {"Authorization", "Bearer #{token}"}]
    body = Jason.encode!(%{message: prompt, provider: "voice"})

    case HTTPoison.post(url, body, headers, recv_timeout: @clawdbot_timeout) do
      {:ok, %{status_code: 200, body: resp_body}} -> parse_clawdbot_response(resp_body)
      {:ok, %{status_code: code}} -> {:error, {:api_error, code}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_clawdbot_response(body) do
    case Jason.decode(body) do
      {:ok, %{"response" => response}} -> {:ok, response}
      {:ok, %{"message" => response}} -> {:ok, response}
      _ -> {:error, :invalid_response}
    end
  end

  defp speak_response(text, guild_id) do
    voice_id = Application.get_env(:soundboard, :elevenlabs_voice_id)
    api_key = Application.get_env(:soundboard, :elevenlabs_api_key)

    if is_nil(api_key) or is_nil(voice_id) do

        Logger.warning("ElevenLabs not configured")
        {:error, :elevenlabs_not_configured}

      else
        generate_and_play_tts(text, guild_id, voice_id, api_key)
    end
  end

  defp generate_and_play_tts(text, guild_id, voice_id, api_key) do
    url = "#{@elevenlabs_api_url}/#{voice_id}"
    headers = [{"xi-api-key", api_key}, {"Content-Type", "application/json"}]
    body = Jason.encode!(%{
      text: text,
      model_id: "eleven_monolingual_v1",
      voice_settings: %{stability: 0.5, similarity_boost: 0.75}
    })

    case HTTPoison.post(url, body, headers, recv_timeout: 30_000) do
      {:ok, %{status_code: 200, body: audio_data}} ->
        play_audio(audio_data, guild_id)

      {:ok, %{status_code: code}} ->
        Logger.warning("ElevenLabs API error: #{code}")
        {:error, {:tts_error, code}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp play_audio(audio_data, guild_id) do
    tmp_file = "/tmp/clawd_response_#{:erlang.unique_integer([:positive])}.mp3"
    File.write!(tmp_file, audio_data)
    Voice.play(guild_id, tmp_file, :url)

    # Clean up after playback
    Task.start(fn ->
      Process.sleep(30_000)
      File.rm(tmp_file)
    end)

    :ok
  end
end
