defmodule Soundboard.Discord.Handler.VoiceRuntime do
  @moduledoc false

  require Logger

  alias Soundboard.AudioPlayer
  alias Soundboard.Discord.Handler.{AutoJoinPolicy, VoiceCommands, VoicePresence}
  alias Soundboard.Discord.Voice

  @type runtime_action :: {:schedule_recheck_alone, String.t(), String.t(), non_neg_integer()}

  def bootstrap do
    Logger.info("Starting DiscordHandler...")

    case AutoJoinPolicy.mode() do
      :enabled -> start_guild_check_task()
      :disabled -> :ok
    end

    :ok
  end

  def join_voice_channel(guild_id, channel_id),
    do: VoiceCommands.join_voice_channel(guild_id, channel_id)

  def leave_voice_channel(guild_id), do: VoiceCommands.leave_voice_channel(guild_id)

  @spec handle_connect(map()) :: [runtime_action()]
  def handle_connect(payload) do
    case AutoJoinPolicy.mode() do
      :enabled -> handle_auto_join_leave(payload)
      :disabled -> []
    end
  end

  @spec handle_disconnect(map()) :: [runtime_action()]
  def handle_disconnect(payload) do
    case AutoJoinPolicy.mode() do
      :enabled -> handle_bot_alone_check(payload.guild_id)
      :disabled -> []
    end
  end

  @spec recheck_alone(String.t(), String.t()) :: [runtime_action()]
  def recheck_alone(guild_id, channel_id) do
    case current_voice_channel_status() do
      {:ok, {^guild_id, ^channel_id}} -> handle_recheck_alone(guild_id, channel_id)
      _ -> Logger.debug("Recheck skipped; voice target changed")
    end

    []
  end

  def get_current_voice_channel do
    case current_voice_channel_status() do
      {:ok, channel} -> channel
      _ -> nil
    end
  end

  def user_voice_channel(guild_id, user_id) do
    case VoicePresence.user_voice_channel(guild_id, user_id) do
      {:ok, channel_id} -> channel_id
      _ -> nil
    end
  end

  def bot_user?(user_id), do: VoicePresence.bot_user?(user_id)

  defp start_guild_check_task do
    Task.start(fn ->
      Logger.info("Starting voice channel check task...")
      Process.sleep(5000)
      check_guilds()
    end)
  end

  defp check_guilds do
    case VoicePresence.cached_guilds() do
      {:ok, []} ->
        Logger.warning("No guilds found in cache. Discord may not be ready.")

      {:ok, guilds} ->
        process_guilds(guilds)

      {:error, reason} ->
        Logger.warning("Guild cache unavailable during bootstrap: #{inspect(reason)}")
    end
  end

  defp process_guilds(guilds) do
    Logger.info("Checking #{length(guilds)} guilds for active voice channels")

    Enum.each(guilds, &check_and_join_voice/1)
  end

  defp check_and_join_voice(guild) do
    voice_states = guild.voice_states
    bot_id = current_bot_id()

    case Enum.find(voice_states, fn vs -> vs.user_id != bot_id && vs.channel_id != nil end) do
      %{channel_id: channel_id} when not is_nil(channel_id) ->
        Logger.info("Auto-joining guild #{guild.id} channel #{channel_id} during bootstrap")
        Voice.join_channel(guild.id, channel_id)
        AudioPlayer.set_voice_channel(guild.id, channel_id)

      _ ->
        :ok
    end
  end

  defp handle_recheck_alone(guild_id, channel_id) do
    case VoicePresence.users_in_channel(guild_id, channel_id) do
      {:ok, users} ->
        Logger.info("Recheck alone: channel #{channel_id} now has #{users} non-bot users")
        maybe_leave_if_bot_alone(guild_id, channel_id, users)

      {:error, reason} ->
        Logger.warning("Recheck skipped because voice state was unavailable: #{inspect(reason)}")
    end
  end

  defp maybe_leave_if_bot_alone(guild_id, channel_id, 0) do
    Logger.info("Recheck confirms bot is alone; leaving channel #{channel_id}")
    leave_voice_channel(guild_id)
  end

  defp maybe_leave_if_bot_alone(_guild_id, _channel_id, _users), do: :ok

  defp handle_bot_alone_check(_guild_id) do
    case current_voice_channel_status() do
      {:ok, {guild_id, channel_id}} -> check_and_maybe_leave(guild_id, channel_id)
      _ -> []
    end
  end

  defp check_and_maybe_leave(guild_id, channel_id) do
    case VoicePresence.users_in_channel(guild_id, channel_id) do
      {:ok, 0} ->
        Logger.info("No non-bot users remaining in channel, leaving now")
        leave_voice_channel(guild_id)
        []

      {:ok, users} ->
        Logger.info("Non-bot users detected (#{users}); scheduling recheck in 1.5s")
        [schedule_recheck(guild_id, channel_id)]

      {:error, reason} ->
        Logger.warning(
          "Skipping leave check because voice state was unavailable: #{inspect(reason)}"
        )

        []
    end
  end

  defp handle_auto_join_leave(payload) do
    if bot_user?(payload.user_id) do
      Logger.debug("Ignoring bot's own voice state update in auto-join logic")
      []
    else
      process_user_voice_update(payload)
    end
  end

  defp process_user_voice_update(payload) do
    case current_voice_channel_status() do
      :not_found when payload.channel_id != nil ->
        handle_bot_not_in_voice(payload)

      {:ok, {guild_id, current_channel_id}} when current_channel_id != payload.channel_id ->
        handle_bot_in_different_channel(guild_id, current_channel_id)

      _ ->
        Logger.debug("No action needed for voice state update")
        []
    end
  end

  defp handle_bot_not_in_voice(payload) do
    case VoicePresence.users_in_channel(payload.guild_id, payload.channel_id) do
      {:ok, users_in_channel} ->
        Logger.info("Found #{users_in_channel} users in channel #{payload.channel_id}")
        maybe_join_channel_for_payload(payload, users_in_channel)
        []

      {:error, reason} ->
        Logger.warning(
          "Skipping auto-join because voice state was unavailable: #{inspect(reason)}"
        )

        []
    end
  end

  defp handle_bot_in_different_channel(guild_id, current_channel_id) do
    case VoicePresence.users_in_channel(guild_id, current_channel_id) do
      {:ok, users} ->
        Logger.info("Current channel #{current_channel_id} has #{users} users")
        handle_current_channel_users(guild_id, current_channel_id, users)

      {:error, reason} ->
        Logger.warning(
          "Skipping channel switch handling because voice state was unavailable: #{inspect(reason)}"
        )

        []
    end
  end

  defp maybe_join_channel_for_payload(_payload, users_in_channel) when users_in_channel <= 0,
    do: :ok

  defp maybe_join_channel_for_payload(payload, users_in_channel) do
    if Voice.ready?(payload.guild_id) do
      Logger.debug("Bot already connected to voice in guild #{payload.guild_id}, skipping join")
    else
      Logger.info("Joining channel #{payload.channel_id} with #{users_in_channel} users")
      join_voice_channel(payload.guild_id, payload.channel_id)
    end
  end

  defp handle_current_channel_users(guild_id, current_channel_id, 0) do
    Logger.info("Bot is alone in channel #{current_channel_id}, leaving")
    leave_voice_channel(guild_id)
    []
  end

  defp handle_current_channel_users(guild_id, current_channel_id, _users) do
    [schedule_recheck(guild_id, current_channel_id)]
  end

  defp schedule_recheck(guild_id, channel_id),
    do: {:schedule_recheck_alone, guild_id, channel_id, 1_500}

  defp current_voice_channel_status do
    case VoicePresence.current_voice_channel() do
      {:ok, channel} ->
        {:ok, channel}

      :not_found ->
        :not_found

      {:error, reason} ->
        Logger.debug("Current voice channel unavailable: #{inspect(reason)}")
        :not_found
    end
  end

  defp current_bot_id do
    case VoicePresence.bot_id() do
      {:ok, bot_id} -> bot_id
      _ -> nil
    end
  end
end
