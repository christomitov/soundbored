defmodule SoundboardWeb.DiscordHandlerTest do
  @moduledoc """
  Tests the DiscordHandler module.
  """
  use Soundboard.DataCase
  alias Ecto.Adapters.SQL.Sandbox
  alias SoundboardWeb.DiscordHandler
  import Mock

  describe "handle_event/1" do
    test "handles voice state updates" do
      # Start with name registration
      start_supervised!({SoundboardWeb.DiscordHandler, name: SoundboardWeb.DiscordHandler})

      # Then allow sandbox access
      Sandbox.allow(
        Soundboard.Repo,
        self(),
        Process.whereis(SoundboardWeb.DiscordHandler)
      )

      mock_guild = %{
        id: "456",
        voice_states: [
          %{
            user_id: "789",
            channel_id: "123",
            guild_id: "456",
            session_id: "abc"
          }
        ]
      }

      with_mocks([
        {Nostrum.Voice, [], [join_channel: fn _, _ -> :ok end]},
        {Nostrum.Cache.GuildCache, [], [get!: fn _guild_id -> mock_guild end]}
      ]) do
        payload = %{
          channel_id: "123",
          guild_id: "456",
          user_id: "789",
          session_id: "abc"
        }

        DiscordHandler.handle_event({:VOICE_STATE_UPDATE, payload, nil})

        # Assert that appropriate actions were taken
        assert_called(Nostrum.Voice.join_channel("456", "123"))
      end
    end
  end
end
