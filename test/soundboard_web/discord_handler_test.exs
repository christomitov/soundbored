defmodule SoundboardWeb.DiscordHandlerTest do
  @moduledoc """
  Tests the DiscordHandler module.
  """
  use Soundboard.DataCase
  alias SoundboardWeb.DiscordHandler
  import Mock
  import ExUnit.CaptureLog

  describe "handle_event/1" do
    test "handles voice state updates" do
      # State GenServer is already started by the application
      # Set up the persistent term to simulate bot being ready
      :persistent_term.put(:soundboard_bot_ready, true)

      # Clean up after test
      on_exit(fn ->
        :persistent_term.erase(:soundboard_bot_ready)
      end)

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

      capture_log(fn ->
        with_mocks([
          {Nostrum.Voice, [],
           [
             join_channel: fn _, _ -> :ok end,
             ready?: fn _ -> false end
           ]},
          {Nostrum.Cache.GuildCache, [], [get!: fn _guild_id -> mock_guild end]},
          {Nostrum.Api.Self, [], [get: fn -> {:ok, %{id: "999"}} end]}
        ]) do
          payload = %{
            channel_id: "123",
            guild_id: "456",
            user_id: "789",
            session_id: "abc"
          }

          # Call the handle_event function directly since it's a callback, not a GenServer
          DiscordHandler.handle_event({:VOICE_STATE_UPDATE, payload, nil})

          # Assert that appropriate actions were taken
          assert_called(Nostrum.Voice.join_channel("456", "123"))
        end
      end)
    end
  end
end
