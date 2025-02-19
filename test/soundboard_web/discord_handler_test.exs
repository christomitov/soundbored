defmodule SoundboardWeb.DiscordHandlerTest do
  use Soundboard.DataCase
  alias SoundboardWeb.DiscordHandler
  import Mock

  describe "handle_event/1" do
    test "handles voice state updates" do
      # Start with name registration
      start_supervised!({SoundboardWeb.DiscordHandler, name: SoundboardWeb.DiscordHandler})

      # Then allow sandbox access
      Ecto.Adapters.SQL.Sandbox.allow(
        Soundboard.Repo,
        self(),
        Process.whereis(SoundboardWeb.DiscordHandler)
      )

      with_mock Nostrum.Voice, join_channel: fn _, _ -> :ok end do
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
