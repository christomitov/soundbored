defmodule Soundboard.Discord.Handler.VoiceRuntime do
  @moduledoc false

  require Logger

  alias Soundboard.AudioPlayer
  alias Soundboard.Discord.{GuildCache, Self, Voice}

  def bootstrap do
    Logger.info("Starting DiscordHandler...")

    case auto_join_mode() do
      :enabled -> start_guild_check_task()
      :disabled -> :ok
    end

    :ok
  end

  def join_voice_channel(guild_id, channel_id) do
    execute_voice_command(
      connected_to_discord?(),
      "Skipping join_voice_channel - not connected to Discord",
      fn ->
        Logger.info("Bot joining voice channel #{channel_id} in guild #{guild_id}")

        run_voice_command("join voice channel", fn -> Voice.join_channel(guild_id, channel_id) end)
      end,
      fn -> AudioPlayer.set_voice_channel(guild_id, channel_id) end,
      fn error_msg -> Logger.error("Error joining voice channel: #{error_msg}") end
    )
  end

  def leave_voice_channel(guild_id) do
    execute_voice_command(
      connected_to_discord?(),
      "Skipping leave_voice_channel - not connected to Discord",
      fn ->
        Logger.info("Bot leaving voice channel in guild #{guild_id}")
        run_voice_command("leave voice channel", fn -> Voice.leave_channel(guild_id) end)
      end,
      fn -> AudioPlayer.set_voice_channel(nil, nil) end,
      fn error_msg -> Logger.error("Error leaving voice channel: #{error_msg}") end
    )
  end

  defp execute_voice_command(true, _skip_message, command_fun, success_fun, error_fun) do
    case command_fun.() do
      :ok -> success_fun.()
      {:error, error_msg} -> error_fun.(error_msg)
    end
  end

  defp execute_voice_command(false, skip_message, _command_fun, _success_fun, _error_fun) do
    Logger.warning(skip_message)
  end

  def handle_connect(payload) do
    case auto_join_mode() do
      :enabled -> handle_auto_join_leave(payload)
      :disabled -> :noop
    end
  end

  def handle_disconnect(payload) do
    case auto_join_mode() do
      :enabled -> handle_bot_alone_check(payload.guild_id)
      :disabled -> :noop
    end
  end

  def recheck_alone(guild_id, channel_id) do
    case get_current_voice_channel() do
      {gid, cid} when gid == guild_id and cid == channel_id ->
        handle_recheck_alone(guild_id, channel_id)

      _ ->
        Logger.debug("Recheck skipped; voice target changed")
    end

    :ok
  end

  def get_current_voice_channel do
    case Self.get() do
      {:ok, %{id: bot_id}} -> find_bot_voice_channel(bot_id)
      _ -> nil
    end
  end

  def user_voice_channel(guild_id, user_id) do
    guild = GuildCache.get!(guild_id)

    case Enum.find(guild.voice_states, fn vs -> vs.user_id == user_id end) do
      nil -> nil
      voice_state -> voice_state.channel_id
    end
  end

  def bot_user?(user_id) do
    case Self.get() do
      {:ok, %{id: bot_id}} -> to_string(bot_id) == to_string(user_id)
      _ -> false
    end
  end

  defp start_guild_check_task do
    Task.start(fn ->
      Logger.info("Starting voice channel check task...")
      Process.sleep(5000)
      check_guilds()
    end)
  end

  defp check_guilds do
    case Enum.to_list(GuildCache.all()) do
      [] -> Logger.warning("No guilds found in cache. Discord may not be ready.")
      guilds -> process_guilds(guilds)
    end
  end

  defp process_guilds(guilds) do
    guilds = Enum.to_list(guilds)
    Logger.info("Found #{length(guilds)} guilds")

    for guild <- guilds do
      Logger.info("Checking guild #{guild.id} for voice channels...")
      check_and_join_voice(guild)
    end
  end

  defp run_voice_command(action, command) do
    case safely_run_voice_command(command) do
      :ok ->
        :ok

      {:error, error_msg} ->
        if rate_limited?(error_msg) do
          Logger.warning("Rate limited while trying to #{action}, retrying in 5 seconds...")
          Process.sleep(5000)
          safely_run_voice_command(command)
        else
          {:error, error_msg}
        end
    end
  end

  defp safely_run_voice_command(command) do
    case command.() do
      :ok -> :ok
      other -> {:error, inspect(other)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp rate_limited?(error_msg) do
    is_binary(error_msg) and String.contains?(String.downcase(error_msg), "rate limit")
  end

  defp connected_to_discord? do
    ready = :persistent_term.get(:soundboard_bot_ready, false)

    if ready do
      try do
        case Self.get() do
          {:ok, _} ->
            Logger.debug("Discord connection check: Connected and ready")
            true

          error ->
            Logger.debug("Discord connection check failed: #{inspect(error)}")
            false
        end
      rescue
        error ->
          Logger.debug("Discord connection check error: #{inspect(error)}")
          false
      end
    else
      Logger.debug("Discord connection check: Bot not ready (READY event not received)")
      false
    end
  end

  defp check_users_in_voice(guild_id, channel_id) do
    cond do
      not valid_discord_id?(guild_id) -> unavailable_voice_state(guild_id, channel_id)
      is_nil(channel_id) -> unavailable_voice_state(guild_id, channel_id)
      true -> count_users_in_channel(guild_id, channel_id)
    end
  end

  defp unavailable_voice_state(guild_id, channel_id) do
    log_voice_cache_warning(guild_id, channel_id)
    :error
  end

  defp count_users_in_channel(guild_id, channel_id) do
    case safe_guild_fetch(guild_id) do
      {:ok, guild} ->
        bot_id = maybe_bot_id()
        voice_states = List.wrap(guild.voice_states)

        users_in_channel =
          voice_states
          |> Enum.count(fn vs -> vs.channel_id == channel_id && vs.user_id != bot_id end)

        log_voice_state_snapshot(channel_id, users_in_channel, bot_id, voice_states)
        {:ok, users_in_channel}

      _ ->
        unavailable_voice_state(guild_id, channel_id)
    end
  end

  defp maybe_bot_id do
    case Self.get() do
      {:ok, %{id: id}} -> id
      _ -> nil
    end
  end

  defp log_voice_state_snapshot(channel_id, users_in_channel, bot_id, voice_states) do
    Logger.info("""
    Voice state check:
    Channel ID: #{channel_id}
    Users in channel: #{users_in_channel} (excluding bot)
    Bot ID: #{bot_id}
    Voice states: #{inspect(voice_states)}
    """)
  end

  defp log_voice_cache_warning(guild_id, channel_id) do
    Logger.warning(
      "check_users_in_voice: cache not ready or invalid target (guild_id=#{inspect(guild_id)}, channel_id=#{inspect(channel_id)})"
    )
  end

  defp safe_guild_fetch(guild_id) do
    case GuildCache.get(guild_id) do
      {:ok, guild} -> {:ok, guild}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp handle_recheck_alone(guild_id, channel_id) do
    case check_users_in_voice(guild_id, channel_id) do
      {:ok, users} ->
        Logger.info("Recheck alone: channel #{channel_id} now has #{users} non-bot users")
        maybe_leave_if_bot_alone(guild_id, channel_id, users)

      :error ->
        Logger.warning("Recheck skipped because voice state was unavailable")
    end
  end

  defp maybe_leave_if_bot_alone(guild_id, channel_id, 0) do
    Logger.info("Recheck confirms bot is alone; leaving channel #{channel_id}")
    leave_voice_channel(guild_id)
  end

  defp maybe_leave_if_bot_alone(_guild_id, _channel_id, _users), do: :ok

  defp find_bot_voice_channel(bot_id) do
    case get_cached_guilds() do
      [] -> get_fallback_voice_channel()
      guilds -> find_voice_channel_in_guilds(guilds, bot_id) || get_fallback_voice_channel()
    end
  end

  defp get_cached_guilds do
    GuildCache.all()
    |> Enum.to_list()
  rescue
    _ -> []
  end

  defp find_voice_channel_in_guilds(guilds, bot_id) do
    Enum.find_value(guilds, fn guild ->
      find_bot_voice_state(guild, bot_id)
    end)
  end

  defp find_bot_voice_state(guild, bot_id) do
    voice_states = guild.voice_states || []

    case Enum.find(voice_states, fn vs -> vs.user_id == bot_id end) do
      %{channel_id: channel_id} when not is_nil(channel_id) -> {guild.id, channel_id}
      _ -> nil
    end
  end

  defp get_fallback_voice_channel do
    case safe_audio_player_voice_channel() do
      {gid, cid} when not is_nil(gid) and not is_nil(cid) -> {gid, cid}
      _ -> nil
    end
  end

  defp safe_audio_player_voice_channel do
    AudioPlayer.current_voice_channel()
  catch
    :exit, _ -> nil
    :error, _ -> nil
    _ -> nil
  end

  defp check_and_join_voice(guild) do
    voice_states = guild.voice_states
    bot_id = maybe_bot_id()

    Logger.info("""
    Checking voice states for guild #{guild.id}:
    Total voice states: #{length(voice_states)}
    Bot ID: #{bot_id}
    Voice states: #{inspect(voice_states)}
    """)

    case Enum.find(voice_states, fn vs ->
           vs.user_id != bot_id && vs.channel_id != nil
         end) do
      %{channel_id: channel_id} = voice_state when not is_nil(channel_id) ->
        Logger.info("""
        Found user in voice channel:
        Channel ID: #{channel_id}
        Voice State: #{inspect(voice_state)}
        Attempting to join...
        """)

        Voice.join_channel(guild.id, channel_id)
        AudioPlayer.set_voice_channel(guild.id, channel_id)

      _ ->
        Logger.info("No users found in voice channels for guild #{guild.id}")
    end
  end

  defp auto_join_mode do
    case Application.get_env(:soundboard, :env) do
      :test -> :enabled
      _ -> if auto_join_enabled?(), do: :enabled, else: :disabled
    end
  end

  defp auto_join_enabled? do
    case System.get_env("AUTO_JOIN") do
      nil -> false
      value -> truthy_value?(value)
    end
  end

  defp truthy_value?(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 in ["true", "1", "yes"]))
  end

  defp handle_bot_alone_check(_guild_id) do
    case get_current_voice_channel() do
      {guild_id, channel_id} ->
        check_and_maybe_leave(guild_id, channel_id)

      _ ->
        :noop
    end
  end

  defp check_and_maybe_leave(guild_id, channel_id) do
    if valid_discord_id?(guild_id) and not is_nil(channel_id) do
      case check_users_in_voice(guild_id, channel_id) do
        {:ok, 0} ->
          Logger.info("No non-bot users remaining in channel, leaving now")
          leave_voice_channel(guild_id)

        {:ok, users} ->
          Logger.info("Non-bot users detected (#{users}); scheduling recheck in 1.5s")
          Process.send_after(self(), {:recheck_alone, guild_id, channel_id}, 1_500)
          :noop

        :error ->
          Logger.warning("Skipping leave check because voice state was unavailable")
          :noop
      end
    else
      Logger.debug(
        "Skipping check_and_maybe_leave due to invalid target: guild_id=#{inspect(guild_id)}, channel_id=#{inspect(channel_id)}"
      )

      :noop
    end
  end

  defp handle_auto_join_leave(payload) do
    Logger.info("Handling auto join/leave for payload: #{inspect(payload)}")

    if bot_user?(payload.user_id) do
      Logger.debug("Ignoring bot's own voice state update in auto-join logic")
      :noop
    else
      process_user_voice_update(payload)
    end
  end

  defp process_user_voice_update(payload) do
    case get_current_voice_channel() do
      nil when payload.channel_id != nil ->
        handle_bot_not_in_voice(payload)

      {guild_id, current_channel_id} when current_channel_id != payload.channel_id ->
        handle_bot_in_different_channel(guild_id, current_channel_id)

      _ ->
        Logger.debug("No action needed for voice state update")
        :noop
    end
  end

  defp handle_bot_not_in_voice(payload) do
    case check_users_in_voice(payload.guild_id, payload.channel_id) do
      {:ok, users_in_channel} ->
        Logger.info("Found #{users_in_channel} users in channel #{payload.channel_id}")
        maybe_join_channel_for_payload(payload, users_in_channel)

      :error ->
        Logger.warning("Skipping auto-join because voice state was unavailable")
    end
  end

  defp handle_bot_in_different_channel(guild_id, current_channel_id) do
    if valid_discord_id?(guild_id) and not is_nil(current_channel_id) do
      case check_users_in_voice(guild_id, current_channel_id) do
        {:ok, users} ->
          Logger.info("Current channel #{current_channel_id} has #{users} users")
          handle_current_channel_users(guild_id, current_channel_id, users)

        :error ->
          Logger.warning("Skipping channel switch handling because voice state was unavailable")
      end
    else
      Logger.debug(
        "Skipping handle_bot_in_different_channel due to invalid target: guild_id=#{inspect(guild_id)}, channel_id=#{inspect(current_channel_id)}"
      )

      :noop
    end
  end

  defp maybe_join_channel_for_payload(_payload, users_in_channel) when users_in_channel <= 0,
    do: :noop

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
  end

  defp handle_current_channel_users(guild_id, current_channel_id, _users) do
    Process.send_after(self(), {:recheck_alone, guild_id, current_channel_id}, 1_500)
  end

  defp valid_discord_id?(value), do: is_integer(value) or (is_binary(value) and value != "")
end
