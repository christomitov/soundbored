defmodule Soundboard.Discord.Handler.VoicePresenceTest do
  use ExUnit.Case, async: false

  import Mock

  alias Soundboard.Discord.GuildCache
  alias Soundboard.Discord.Handler.VoicePresence

  describe "find_user_voice_channel/1" do
    test "returns {:ok, {guild_id, channel_id}} when user is in a voice channel" do
      guilds = [
        %{
          id: "guild-1",
          voice_states: [
            %{user_id: "user-99", channel_id: "ch-5", guild_id: "guild-1", session_id: "s1"}
          ]
        }
      ]

      with_mock GuildCache, all: fn -> guilds end do
        assert VoicePresence.find_user_voice_channel("user-99") == {:ok, {"guild-1", "ch-5"}}
      end
    end

    test "returns :not_found when user is in no guild" do
      guilds = [
        %{
          id: "guild-1",
          voice_states: [
            %{user_id: "other-user", channel_id: "ch-5", guild_id: "guild-1", session_id: "s1"}
          ]
        }
      ]

      with_mock GuildCache, all: fn -> guilds end do
        assert VoicePresence.find_user_voice_channel("user-99") == :not_found
      end
    end

    test "returns :not_found when user has no channel_id" do
      guilds = [
        %{
          id: "guild-1",
          voice_states: [
            %{user_id: "user-99", channel_id: nil, guild_id: "guild-1", session_id: "s1"}
          ]
        }
      ]

      with_mock GuildCache, all: fn -> guilds end do
        assert VoicePresence.find_user_voice_channel("user-99") == :not_found
      end
    end

    test "searches across multiple guilds" do
      guilds = [
        %{id: "guild-1", voice_states: []},
        %{
          id: "guild-2",
          voice_states: [
            %{user_id: "user-99", channel_id: "ch-7", guild_id: "guild-2", session_id: "s2"}
          ]
        }
      ]

      with_mock GuildCache, all: fn -> guilds end do
        assert VoicePresence.find_user_voice_channel("user-99") == {:ok, {"guild-2", "ch-7"}}
      end
    end

    test "returns :not_found when guild cache is unavailable" do
      with_mock GuildCache, all: fn -> raise "cache unavailable" end do
        assert VoicePresence.find_user_voice_channel("user-99") == :not_found
      end
    end
  end
end
