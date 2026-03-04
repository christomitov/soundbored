defmodule Soundboard.Discord.GuildCache do
  @moduledoc false

  alias EDA.Cache

  def all do
    Cache.guilds()
    |> Enum.map(&normalize_guild/1)
  end

  def get(guild_id) do
    case Cache.get_guild(to_id(guild_id)) do
      nil -> :error
      guild -> {:ok, normalize_guild(guild)}
    end
  end

  def get!(guild_id) do
    case get(guild_id) do
      {:ok, guild} -> guild
      _ -> raise "guild #{guild_id} not found in cache"
    end
  end

  defp normalize_guild(guild) do
    guild_id = map_get(guild, "id")
    channels = Cache.channels_for_guild(guild_id)
    voice_states = Cache.voice_states(guild_id)

    %{
      id: guild_id,
      name: map_get(guild, "name"),
      channels: normalize_channels(channels, guild_id),
      voice_states: Enum.map(voice_states, &normalize_voice_state(&1, guild_id))
    }
  end

  defp normalize_channels(channels, guild_id) do
    Enum.reduce(channels, %{}, fn channel, acc ->
      channel_id = map_get(channel, "id")

      Map.put(acc, channel_id, %{
        id: channel_id,
        guild_id: guild_id,
        name: map_get(channel, "name")
      })
    end)
  end

  defp normalize_voice_state(voice_state, guild_id) do
    %{
      guild_id: guild_id,
      channel_id: map_get(voice_state, "channel_id"),
      user_id: map_get(voice_state, "user_id"),
      session_id: map_get(voice_state, "session_id")
    }
  end

  defp map_get(map, key) when is_map(map) do
    case map do
      %{^key => value} ->
        value

      _ ->
        atom_key = String.to_atom(key)
        Map.get(map, atom_key)
    end
  end

  defp to_id(value) when is_integer(value), do: Integer.to_string(value)
  defp to_id(value), do: to_string(value)
end
