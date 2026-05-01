defmodule Soundboard.Discord.Handler.SoundEffects do
  @moduledoc false

  require Logger

  alias Soundboard.{AudioPlayer, Sounds}
  alias Soundboard.Discord.Handler.{AutoJoinPolicy, VoiceRuntime}

  def handle_join(user_id, previous_state, guild_id, channel_id) do
    is_join_event =
      case previous_state do
        nil -> true
        {nil, _} -> true
        {prev_channel, _} -> prev_channel != channel_id
      end

    Logger.info(
      "Join sound check - User: #{user_id}, Previous: #{inspect(previous_state)}, New channel: #{channel_id}, Is join: #{is_join_event}"
    )

    if is_join_event do
      play_join_sound(user_id, guild_id, channel_id)
    else
      :noop
    end
  end

  def handle_leave(user_id) do
    case Sounds.get_user_leave_sound_by_discord_id(user_id) do
      leave_sound when is_binary(leave_sound) ->
        Logger.info("Playing leave sound: #{leave_sound}")
        AudioPlayer.play_sound(leave_sound, "System")

      _ ->
        :noop
    end
  end

  defp play_join_sound(user_id, guild_id, channel_id) do
    join_sound = Sounds.get_user_join_sound_by_discord_id(user_id)

    Logger.info("Join sound query result for user #{user_id}: #{inspect(join_sound)}")

    case join_sound do
      join_sound when is_binary(join_sound) ->
        Logger.info("Playing join sound immediately: #{join_sound}")
        maybe_join_for_sound(guild_id, channel_id)
        AudioPlayer.play_sound(join_sound, "System")

      _ ->
        Logger.info("No join sound found for user #{user_id}")
        :noop
    end
  end

  defp maybe_join_for_sound(guild_id, channel_id) do
    if AutoJoinPolicy.mode() == :play && VoiceRuntime.get_current_voice_channel() == nil do
      Logger.info("Auto-joining #{guild_id}/#{channel_id} to play join sound")
      VoiceRuntime.join_voice_channel(guild_id, channel_id)
    end
  end
end
