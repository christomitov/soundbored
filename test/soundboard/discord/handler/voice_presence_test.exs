defmodule Soundboard.Discord.Handler.VoicePresenceTest do
  use ExUnit.Case, async: false

  import Mock

  alias Soundboard.Discord.GuildCache
  alias Soundboard.Discord.Handler.VoicePresence

  test "find_user_voice_channel looks only in the given guild" do
    guilds = [
      %{
        id: "guild-1",
        voice_states: [
          %{user_id: "in-1", channel_id: "ch-5"},
          %{user_id: "idle", channel_id: nil}
        ]
      },
      %{id: "guild-2", voice_states: [%{user_id: "in-2", channel_id: "ch-7"}]}
    ]

    table = [
      {"in-1", "guild-1", {:ok, {"guild-1", "ch-5"}}},
      {"in-2", "guild-1", :not_found},
      {"in-2", "guild-2", {:ok, {"guild-2", "ch-7"}}},
      {"idle", "guild-1", :not_found},
      {"nobody", "guild-1", :not_found}
    ]

    with_mock GuildCache, all: fn -> guilds end do
      for {user, guild, expected} <- table do
        assert {user, guild, VoicePresence.find_user_voice_channel(user, guild)} ==
                 {user, guild, expected}
      end
    end
  end

  test "cached_guilds reports an unavailable cache instead of raising" do
    with_mock GuildCache, all: fn -> raise "cache unavailable" end do
      assert {:error, {:guild_cache_unavailable, "cache unavailable"}} =
               VoicePresence.cached_guilds()
    end
  end
end
