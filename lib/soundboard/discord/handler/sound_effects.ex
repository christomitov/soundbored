defmodule Soundboard.Discord.Handler.SoundEffects do
  @moduledoc false

  require Logger

  alias Soundboard.{AudioPlayer, Sounds}

  def handle_join(user_id, previous_state, new_channel_id) do
    is_join_event =
      case previous_state do
        nil -> true
        {nil, _} -> true
        {prev_channel, _} -> prev_channel != new_channel_id
      end

    Logger.info(
      "Join sound check - User: #{user_id}, Previous: #{inspect(previous_state)}, New channel: #{new_channel_id}, Is join: #{is_join_event}"
    )

    if is_join_event do
      play_join_sound(user_id)
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

  defp play_join_sound(user_id) do
    join_sound = Sounds.get_user_join_sound_by_discord_id(user_id)

    Logger.info("Join sound query result for user #{user_id}: #{inspect(join_sound)}")

    case join_sound do
      join_sound when is_binary(join_sound) ->
        Logger.info("Playing join sound immediately: #{join_sound}")
        AudioPlayer.play_sound(join_sound, "System")

      _ ->
        Logger.info("No join sound found for user #{user_id}")
        :noop
    end
  end
end
