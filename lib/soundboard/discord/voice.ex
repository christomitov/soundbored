defmodule Soundboard.Discord.Voice do
  @moduledoc false

  alias EDA.Voice, as: EDAVoice

  @connected_error "Must be connected to voice channel to play audio."
  @not_ready_error "Voice session is still negotiating encryption."
  @already_playing_error "Audio already playing in voice channel."

  def join_channel(guild_id, channel_id) do
    EDAVoice.join(to_id(guild_id), to_id(channel_id))
  end

  def leave_channel(guild_id) do
    EDAVoice.leave(to_id(guild_id))
  end

  def play(guild_id, input, type, _opts \\ []) do
    case EDAVoice.play(to_id(guild_id), input, type) do
      :ok -> :ok
      {:error, :already_playing} -> {:error, @already_playing_error}
      {:error, :not_connected} -> {:error, @connected_error}
      {:error, :not_ready} -> {:error, @not_ready_error}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def stop(guild_id) do
    EDAVoice.stop(to_id(guild_id))
  end

  def ready?(guild_id) do
    EDAVoice.ready?(to_id(guild_id))
  end

  def channel_id(guild_id) do
    EDAVoice.channel_id(to_id(guild_id))
  end

  def playing?(guild_id) do
    EDAVoice.playing?(to_id(guild_id))
  end

  # Compatibility shape for existing RTP probe code.
  def get_voice(guild_id) do
    case EDAVoice.get_voice_state(to_id(guild_id)) do
      {:ok, %{sequence: seq} = state} -> %{rtp_sequence: seq, state: state}
      _ -> nil
    end
  end

  defp to_id(nil), do: nil
  defp to_id(value) when is_integer(value), do: Integer.to_string(value)
  defp to_id(value), do: to_string(value)
end
