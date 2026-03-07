defmodule Soundboard.Discord.Handler.VoicePresence do
  @moduledoc false

  require Logger

  alias Soundboard.AudioPlayer
  alias Soundboard.Discord.{BotIdentity, GuildCache}

  def current_voice_channel do
    with {:ok, bot_id} <- bot_id() do
      case find_bot_voice_channel(bot_id) do
        nil -> :not_found
        channel -> {:ok, channel}
      end
    end
  end

  def user_voice_channel(guild_id, user_id) do
    case GuildCache.get(guild_id) do
      {:ok, guild} -> find_user_voice_channel(guild, user_id)
      :error -> {:error, {:guild_unavailable, guild_id}}
    end
  end

  def bot_user?(user_id) do
    case bot_id() do
      {:ok, bot_id} -> to_string(bot_id) == to_string(user_id)
      _ -> false
    end
  end

  def bot_id do
    case BotIdentity.fetch() do
      {:ok, %{id: id}} when not is_nil(id) -> {:ok, id}
      {:ok, _} -> {:error, :bot_identity_missing}
      {:error, reason} -> {:error, {:bot_identity_unavailable, reason}}
      other -> {:error, {:bot_identity_unavailable, other}}
    end
  end

  def cached_guilds do
    {:ok, GuildCache.all() |> Enum.to_list()}
  rescue
    error -> {:error, {:guild_cache_unavailable, Exception.message(error)}}
  end

  def users_in_channel(guild_id, channel_id) do
    cond do
      not valid_discord_id?(guild_id) ->
        {:error, {:invalid_voice_target, %{guild_id: guild_id, channel_id: channel_id}}}

      is_nil(channel_id) ->
        {:error, {:invalid_voice_target, %{guild_id: guild_id, channel_id: channel_id}}}

      true ->
        count_users_in_channel(guild_id, channel_id)
    end
  end

  defp count_users_in_channel(guild_id, channel_id) do
    case GuildCache.get(guild_id) do
      {:ok, guild} ->
        bot_id = bot_id_value()
        voice_states = List.wrap(guild.voice_states)

        users_in_channel =
          voice_states
          |> Enum.count(fn vs -> vs.channel_id == channel_id && vs.user_id != bot_id end)

        log_voice_state_snapshot(channel_id, users_in_channel, bot_id, voice_states)
        {:ok, users_in_channel}

      :error ->
        {:error, {:guild_unavailable, guild_id}}
    end
  end

  defp bot_id_value do
    case bot_id() do
      {:ok, id} -> id
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

  defp find_bot_voice_channel(bot_id) do
    case cached_guilds() do
      {:ok, []} ->
        fallback_voice_channel()

      {:ok, guilds} ->
        find_voice_channel_in_guilds(guilds, bot_id) || fallback_voice_channel()

      {:error, reason} ->
        Logger.debug("Guild cache unavailable for bot voice channel lookup: #{inspect(reason)}")
        fallback_voice_channel()
    end
  end

  defp find_user_voice_channel(guild, user_id) do
    case Enum.find(guild.voice_states, fn vs -> vs.user_id == user_id end) do
      nil -> :not_found
      voice_state -> {:ok, voice_state.channel_id}
    end
  end

  defp find_voice_channel_in_guilds(guilds, bot_id) do
    Enum.find_value(guilds, &voice_channel_for_guild(&1, bot_id))
  end

  defp voice_channel_for_guild(guild, bot_id) do
    guild.voice_states
    |> List.wrap()
    |> Enum.find_value(fn
      %{user_id: ^bot_id, channel_id: channel_id} when not is_nil(channel_id) ->
        {guild.id, channel_id}

      _ ->
        nil
    end)
  end

  defp fallback_voice_channel do
    case AudioPlayer.current_voice_channel() do
      {:ok, {gid, cid}} when not is_nil(gid) and not is_nil(cid) ->
        {gid, cid}

      {:ok, _} ->
        nil

      {:error, reason} ->
        Logger.debug("Audio player voice channel unavailable: #{inspect(reason)}")
        nil
    end
  end

  defp valid_discord_id?(value), do: is_integer(value) or (is_binary(value) and value != "")
end
