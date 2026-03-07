defmodule Soundboard.AudioPlayer.VoiceSession do
  @moduledoc false

  require Logger

  alias Soundboard.AudioPlayer.State
  alias Soundboard.Discord.Voice

  @spec normalize_channel(term(), term()) :: {String.t(), String.t()} | nil
  def normalize_channel(guild_id, channel_id) do
    if is_nil(guild_id) or is_nil(channel_id) do
      nil
    else
      {guild_id, channel_id}
    end
  end

  @spec maintain_connection(State.t()) :: State.t()
  def maintain_connection(%State{voice_channel: {guild_id, channel_id}} = state)
      when not is_nil(guild_id) and not is_nil(channel_id) do
    guild_id
    |> maintenance_status(channel_id)
    |> perform_maintenance(state)
  end

  def maintain_connection(%State{} = state), do: state

  defp maintenance_status(guild_id, channel_id) do
    %{
      guild_id: guild_id,
      channel_id: channel_id,
      joined?: Voice.channel_id(guild_id) == to_string(channel_id),
      ready?: voice_ready(guild_id),
      playing?: voice_playing(guild_id)
    }
  end

  defp voice_ready(guild_id) do
    case safe_voice_ready(guild_id) do
      {:ok, value} ->
        value

      {:error, reason} ->
        Logger.warning("Voice readiness unavailable for guild #{guild_id}: #{inspect(reason)}")
        false
    end
  end

  defp voice_playing(guild_id) do
    case safe_voice_playing(guild_id) do
      {:ok, value} ->
        value

      {:error, reason} ->
        Logger.warning(
          "Voice playback status unavailable for guild #{guild_id}: #{inspect(reason)}; continuing maintenance"
        )

        false
    end
  end

  defp perform_maintenance(%{playing?: true}, state), do: state
  defp perform_maintenance(%{joined?: true, ready?: true}, state), do: state

  defp perform_maintenance(%{joined?: true} = status, state) do
    Logger.warning(
      "Voice session unready for guild #{status.guild_id} in channel #{status.channel_id}, attempting refresh"
    )

    attempt_voice_join(state, status.guild_id, status.channel_id, "refresh")
  end

  defp perform_maintenance(status, state) do
    Logger.warning(
      "Voice channel mismatch for guild #{status.guild_id}, attempting to rejoin #{status.channel_id}"
    )

    attempt_voice_join(state, status.guild_id, status.channel_id, "rejoin")
  end

  defp attempt_voice_join(state, guild_id, channel_id, action) do
    case safe_join_voice_channel(guild_id, channel_id) do
      :ok ->
        state

      {:error, reason} ->
        Logger.error("Failed to #{action} voice channel: #{inspect(reason)}")
        %{state | voice_channel: nil}
    end
  end

  defp safe_voice_ready(guild_id) do
    {:ok, Voice.ready?(guild_id)}
  rescue
    error -> {:error, {:voice_not_ready, Exception.message(error)}}
  end

  defp safe_voice_playing(guild_id) do
    {:ok, Voice.playing?(guild_id)}
  rescue
    error -> {:error, {:voice_playing_unavailable, Exception.message(error)}}
  end

  defp safe_join_voice_channel(guild_id, channel_id) do
    Voice.join_channel(guild_id, channel_id)
    :ok
  rescue
    error -> {:error, {:voice_join_failed, Exception.message(error)}}
  end
end
