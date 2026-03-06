defmodule SoundboardWeb.DiscordHandlerTest do
  @moduledoc """
  Tests the DiscordHandler module.
  """
  use Soundboard.DataCase

  import ExUnit.CaptureLog
  import Mock

  alias Soundboard.{Accounts.User, Repo, Sound, UserSoundSetting}
  alias Soundboard.Discord.Voice
  alias SoundboardWeb.DiscordHandler

  setup do
    :persistent_term.put(:soundboard_bot_ready, true)

    on_exit(fn ->
      :persistent_term.erase(:soundboard_bot_ready)
    end)

    :ok
  end

  describe "handle_event/1" do
    test "handles voice state updates" do
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
          {Soundboard.Discord.Voice, [],
           [
             join_channel: fn _, _ -> :ok end,
             ready?: fn _ -> false end
           ]},
          {Soundboard.Discord.GuildCache, [], [get: fn _guild_id -> {:ok, mock_guild} end]},
          {Soundboard.Discord.Self, [], [get: fn -> {:ok, %{id: "999"}} end]}
        ]) do
          payload = %{
            channel_id: "123",
            guild_id: "456",
            user_id: "789",
            session_id: "abc"
          }

          DiscordHandler.handle_event({:VOICE_STATE_UPDATE, payload, nil})

          assert_called(Voice.join_channel("456", "123"))
        end
      end)
    end

    test "does not auto-join when guild cache is unavailable" do
      {:ok, recorder} = Agent.start_link(fn -> [] end)

      capture_log(fn ->
        with_mocks([
          {Soundboard.Discord.Voice, [],
           [
             join_channel: fn guild_id, channel_id ->
               Agent.update(recorder, &(&1 ++ [{guild_id, channel_id}]))
               :ok
             end,
             ready?: fn _ -> false end
           ]},
          {Soundboard.Discord.GuildCache, [],
           [all: fn -> [] end, get: fn _guild_id -> :error end]},
          {Soundboard.Discord.Self, [], [get: fn -> {:ok, %{id: "999"}} end]}
        ]) do
          payload = %{
            channel_id: "123",
            guild_id: "456",
            user_id: "789",
            session_id: "abc"
          }

          DiscordHandler.handle_event({:VOICE_STATE_UPDATE, payload, nil})

          assert Agent.get(recorder, & &1) == []
        end
      end)
    end

    test "plays join sounds immediately without artificial delay" do
      user = insert_user!(%{discord_id: "555", username: "joiner"})
      sound = insert_sound!(user, %{filename: "join.mp3"})
      insert_user_sound_setting!(user, sound, %{is_join_sound: true})

      bot_id = "999"
      guild_id = "456"
      channel_id = "123"

      guild = %{
        id: guild_id,
        voice_states: [
          %{user_id: bot_id, channel_id: channel_id, guild_id: guild_id, session_id: "bot"},
          %{
            user_id: user.discord_id,
            channel_id: channel_id,
            guild_id: guild_id,
            session_id: "abc"
          }
        ]
      }

      {:ok, recorder} = Agent.start_link(fn -> [] end)

      capture_log(fn ->
        with_mocks([
          {Soundboard.Discord.GuildCache, [], [all: fn -> [guild] end]},
          {Soundboard.Discord.Self, [], [get: fn -> {:ok, %{id: bot_id}} end]},
          {SoundboardWeb.AudioPlayer, [],
           [
             play_sound: fn filename, played_by ->
               Agent.update(recorder, &(&1 ++ [{:play_sound, filename, played_by}]))
               :ok
             end
           ]}
        ]) do
          payload = %{
            channel_id: channel_id,
            guild_id: guild_id,
            user_id: user.discord_id,
            session_id: "abc"
          }

          DiscordHandler.handle_event({:VOICE_STATE_UPDATE, payload, nil})

          assert Agent.get(recorder, & &1) == [{:play_sound, "join.mp3", "System"}]
        end
      end)
    end

    test "plays leave sounds before auto-leaving the voice channel" do
      user = insert_user!(%{discord_id: "556", username: "leaver"})
      sound = insert_sound!(user, %{filename: "leave.mp3"})
      insert_user_sound_setting!(user, sound, %{is_leave_sound: true})

      bot_id = "999"
      guild_id = "456"
      channel_id = "123"

      guild = %{
        id: guild_id,
        voice_states: [
          %{user_id: bot_id, channel_id: channel_id, guild_id: guild_id, session_id: "bot"}
        ]
      }

      {:ok, recorder} = Agent.start_link(fn -> [] end)

      capture_log(fn ->
        with_mocks([
          {Soundboard.Discord.GuildCache, [],
           [
             all: fn -> [guild] end,
             get: fn ^guild_id -> {:ok, guild} end
           ]},
          {Soundboard.Discord.Self, [], [get: fn -> {:ok, %{id: bot_id}} end]},
          {Soundboard.Discord.Voice, [],
           [
             leave_channel: fn ^guild_id ->
               Agent.update(recorder, &(&1 ++ [:leave_channel]))
               :ok
             end
           ]},
          {SoundboardWeb.AudioPlayer, [],
           [
             play_sound: fn filename, played_by ->
               Agent.update(recorder, &(&1 ++ [{:play_sound, filename, played_by}]))
               :ok
             end,
             set_voice_channel: fn guild, channel ->
               Agent.update(recorder, &(&1 ++ [{:set_voice_channel, guild, channel}]))
               :ok
             end
           ]}
        ]) do
          payload = %{
            channel_id: nil,
            guild_id: guild_id,
            user_id: user.discord_id,
            session_id: "gone"
          }

          DiscordHandler.handle_event({:VOICE_STATE_UPDATE, payload, nil})

          assert Agent.get(recorder, & &1) == [
                   {:play_sound, "leave.mp3", "System"},
                   :leave_channel,
                   {:set_voice_channel, nil, nil}
                 ]
        end
      end)
    end

    test "voice commands update the audio player once after the Discord call succeeds" do
      guild_id = "456"
      channel_id = "123"
      user_id = "777"

      guild = %{
        id: guild_id,
        voice_states: [
          %{user_id: user_id, channel_id: channel_id, guild_id: guild_id, session_id: "voice"}
        ]
      }

      {:ok, recorder} = Agent.start_link(fn -> [] end)

      capture_log(fn ->
        with_mocks([
          {Soundboard.Discord.GuildCache, [], [get!: fn ^guild_id -> guild end]},
          {Soundboard.Discord.Self, [], [get: fn -> {:ok, %{id: "999"}} end]},
          {Soundboard.Discord.Message, [], [create: fn _, _ -> :ok end]},
          {Soundboard.Discord.Voice, [],
           [
             join_channel: fn ^guild_id, ^channel_id ->
               Agent.update(recorder, &(&1 ++ [{:join_channel, guild_id, channel_id}]))
               :ok
             end,
             leave_channel: fn ^guild_id ->
               Agent.update(recorder, &(&1 ++ [{:leave_channel, guild_id}]))
               :ok
             end
           ]},
          {SoundboardWeb.AudioPlayer, [],
           [
             set_voice_channel: fn guild, channel ->
               Agent.update(recorder, &(&1 ++ [{:set_voice_channel, guild, channel}]))
               :ok
             end
           ]}
        ]) do
          DiscordHandler.handle_event({
            :MESSAGE_CREATE,
            %{content: "!join", guild_id: guild_id, channel_id: "text", author: %{id: user_id}},
            nil
          })

          DiscordHandler.handle_event({
            :MESSAGE_CREATE,
            %{content: "!leave", guild_id: guild_id, channel_id: "text", author: %{id: user_id}},
            nil
          })

          assert Agent.get(recorder, & &1) == [
                   {:join_channel, guild_id, channel_id},
                   {:set_voice_channel, guild_id, channel_id},
                   {:leave_channel, guild_id},
                   {:set_voice_channel, nil, nil}
                 ]
        end
      end)
    end
  end

  defp insert_user!(attrs) do
    %User{}
    |> User.changeset(Map.put_new(attrs, :avatar, "avatar.png"))
    |> Repo.insert!()
  end

  defp insert_sound!(user, attrs) do
    attrs =
      attrs
      |> Map.put_new(:user_id, user.id)
      |> Map.put_new(:source_type, "local")
      |> Map.put_new(:volume, 1.0)

    %Sound{}
    |> Sound.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_user_sound_setting!(user, sound, attrs) do
    attrs =
      attrs
      |> Map.put(:user_id, user.id)
      |> Map.put(:sound_id, sound.id)

    %UserSoundSetting{}
    |> UserSoundSetting.changeset(attrs)
    |> Repo.insert!()
  end
end
