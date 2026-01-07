defmodule Soundboard.VoiceListener.ClawdbotAPI do
  @moduledoc """
  Handles communication with Clawdbot for processing voice queries.
  
  When a wake word is detected, this module sends the query and context
  to Clawdbot's API and plays the response via ElevenLabs TTS.
  """
  require Logger
  
  alias SoundboardWeb.AudioPlayer
  
  @elevenlabs_api_url "https://api.elevenlabs.io/v1/text-to-speech"
  @clawdbot_timeout 60_000
  
  @doc """
  Processes a voice query by sending it to Clawdbot and playing the response.
  """
  def process_query(query, context, guild_id) do
    Logger.info("Processing voice query: #{query}")
    
    clawdbot_url = Application.get_env(:soundboard, :clawdbot_api_url)
    clawdbot_token = Application.get_env(:soundboard, :clawdbot_api_token)
    
    if is_nil(clawdbot_url) do
      Logger.warning("Clawdbot API URL not configured")
      {:error, :not_configured}
    else
      prompt = build_prompt(query, context)
      
      case send_to_clawdbot(prompt, clawdbot_url, clawdbot_token) do
        {:ok, response} ->
          Logger.info("Got Clawdbot response: #{String.slice(response, 0, 100)}...")
          speak_response(response, guild_id)
        {:error, reason} ->
          Logger.error("Clawdbot query failed: #{inspect(reason)}")
          {:error, reason}
      end
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
  
  defp send_to_clawdbot(prompt, url, token) do
    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{token}"}
    ]
    
    body = Jason.encode!(%{
      message: prompt,
      provider: "voice"
    })
    
    case HTTPoison.post(url, body, headers, recv_timeout: @clawdbot_timeout) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"response" => response}} -> {:ok, response}
          {:ok, %{"message" => response}} -> {:ok, response}
          {:ok, data} -> {:ok, inspect(data)}
          _ -> {:error, :invalid_response}
        end
      {:ok, %{status_code: code, body: body}} ->
        Logger.warning("Clawdbot API error (#{code}): #{body}")
        {:error, {:api_error, code}}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp speak_response(text, guild_id) do
    voice_id = Application.get_env(:soundboard, :elevenlabs_voice_id)
    api_key = Application.get_env(:soundboard, :elevenlabs_api_key)
    
    if is_nil(api_key) or is_nil(voice_id) do
      Logger.warning("ElevenLabs not configured")
      {:error, :elevenlabs_not_configured}
    else
      url = "#{@elevenlabs_api_url}/#{voice_id}"
      
      headers = [
        {"xi-api-key", api_key},
        {"Content-Type", "application/json"}
      ]
      
      body = Jason.encode!(%{
        text: text,
        model_id: "eleven_monolingual_v1",
        voice_settings: %{
          stability: 0.5,
          similarity_boost: 0.75
        }
      })
      
      case HTTPoison.post(url, body, headers, recv_timeout: 30_000) do
        {:ok, %{status_code: 200, body: audio_data}} ->
          # Play audio through AudioPlayer
          AudioPlayer.play_audio_data(audio_data, "audio/mpeg")
          :ok
        {:ok, %{status_code: code, body: body}} ->
          Logger.warning("ElevenLabs API error (#{code}): #{body}")
          {:error, {:tts_error, code}}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
