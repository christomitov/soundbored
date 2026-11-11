defmodule Soundboard.Discord.HandlerTest do
  @moduledoc """
  Discord gateway events through `Soundboard.Discord.Handler.handle_event/1`.
  """
  use Soundboard.DataCase, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Soundboard.{Accounts.User, AudioPlayer, FakeVoice, Repo, Sound, UserSoundSetting}
  alias Soundboard.Discord.{BotIdentity, GuildCache, Handler, Message}

  @bot_id "999"

  setup do
    Application.put_env(:soundboard, :bot_ready, true)
    guild_id = "handler-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Application.delete_env(:soundboard, :bot_ready)
      System.delete_env("AUTO_JOIN")
      if pid = AudioPlayer.server_pid(guild_id), do: GenServer.stop(pid)
    end)

    %{guild_id: guild_id}
  end

  describe "presence mode" do
    setup do
      System.put_env("AUTO_JOIN", "presence")
      :ok
    end

    test "the bot joins the channel a user joins", %{guild_id: guild_id} do
      FakeVoice.claim(guild_id, ready: false)
      guild = %{id: guild_id, voice_states: [voice_state(guild_id, "789", "123")]}

      capture_log(fn ->
        with_mocks([cache(guild), bot()]) do
          Handler.handle_event({:VOICE_STATE_UPDATE, payload(guild_id, "789", "123"), nil})
        end
      end)

      assert_received {:fake_voice, ^guild_id, {:join, "123"}}
      assert AudioPlayer.current_voice_channel(guild_id) == {:ok, {guild_id, "123"}}
    end

    test "the bot does not join when the guild cache is unavailable", %{guild_id: guild_id} do
      FakeVoice.claim(guild_id, ready: false)

      capture_log(fn ->
        with_mocks([
          {GuildCache, [], [all: fn -> [] end, get: fn _guild_id -> :error end]},
          bot()
        ]) do
          Handler.handle_event({:VOICE_STATE_UPDATE, payload(guild_id, "789", "123"), nil})
        end
      end)

      refute_received {:fake_voice, ^guild_id, {:join, _}}
      assert AudioPlayer.current_voice_channel(guild_id) == {:ok, nil}
    end
  end

  describe "join and leave sounds" do
    test "plays the user's join sound on first join", %{guild_id: guild_id} do
      user = insert_user!(%{discord_id: "555", username: "joiner"})
      join_sound!(user, guild_id)

      guild = %{
        id: guild_id,
        voice_states: [
          voice_state(guild_id, @bot_id, "123"),
          voice_state(guild_id, user.discord_id, "123")
        ]
      }

      assert played_sounds(guild_id, [cache(guild)], fn ->
               Handler.handle_event(
                 {:VOICE_STATE_UPDATE, payload(guild_id, user.discord_id, "123"), nil}
               )
             end) == [{:play_sound, "join.mp3", "System"}]
    end

    test "does not play join sounds when the user switches voice channels",
         %{guild_id: guild_id} do
      user = insert_user!(%{discord_id: "557", username: "switcher"})
      join_sound!(user, guild_id)

      assert played_sounds(guild_id, [], fn ->
               Handler.State.update_state(user.discord_id, "ch-a", "session-1")

               Handler.handle_event(
                 {:VOICE_STATE_UPDATE, payload(guild_id, user.discord_id, "ch-b", "session-2"),
                  nil}
               )
             end) == []
    end

    test "does not play join sounds on same-channel voice state updates", %{guild_id: guild_id} do
      user = insert_user!(%{discord_id: "558", username: "muter"})
      join_sound!(user, guild_id)

      assert played_sounds(guild_id, [], fn ->
               Handler.State.update_state(user.discord_id, "ch-a", "session-1")

               Handler.handle_event(
                 {:VOICE_STATE_UPDATE, payload(guild_id, user.discord_id, "ch-a", "session-1"),
                  nil}
               )
             end) == []
    end

    test "still plays join sounds when a user rejoins after disconnecting",
         %{guild_id: guild_id} do
      user = insert_user!(%{discord_id: "559", username: "rejoiner"})
      join_sound!(user, guild_id)

      guild = %{
        id: guild_id,
        voice_states: [
          voice_state(guild_id, @bot_id, "ch-b"),
          voice_state(guild_id, user.discord_id, "ch-b")
        ]
      }

      assert played_sounds(guild_id, [cache(guild)], fn ->
               Handler.State.update_state(user.discord_id, nil, "session-1")

               Handler.handle_event(
                 {:VOICE_STATE_UPDATE, payload(guild_id, user.discord_id, "ch-b", "session-2"),
                  nil}
               )
             end) == [{:play_sound, "join.mp3", "System"}]
    end

    test "plays leave sounds before auto-leaving the voice channel", %{guild_id: guild_id} do
      user = insert_user!(%{discord_id: "556", username: "leaver"})
      sound = insert_sound!(user, %{filename: "leave.mp3", guild_id: guild_id})
      insert_user_sound_setting!(user, sound, %{guild_id: guild_id, is_leave_sound: true})
      guild = %{id: guild_id, voice_states: [voice_state(guild_id, @bot_id, "123")]}

      assert played_sounds(guild_id, [cache(guild)], fn ->
               Handler.handle_event(
                 {:VOICE_STATE_UPDATE, payload(guild_id, user.discord_id, nil, "gone"), nil}
               )
             end) == [{:play_sound, "leave.mp3", "System"}, {:last_user_left, guild_id}]
    end
  end

  test "schedules runtime follow-up messages from the handler boundary" do
    payload = %{channel_id: "123", guild_id: "456", user_id: @bot_id, session_id: "abc"}

    with_mocks([
      {Soundboard.Discord.Handler.VoiceRuntime, [],
       [
         bot_user?: fn _ -> true end,
         handle_connect: fn ^payload -> [{:schedule_recheck_alone, "456", "123", 0}] end
       ]}
    ]) do
      assert {:noreply, nil} =
               Handler.handle_cast({:eda_event, {:VOICE_STATE_UPDATE, payload, nil}}, nil)

      assert_receive {:recheck_alone, "456", "123"}
    end
  end

  describe "voice commands" do
    test "!join and !leave move the bot and confirm in chat", %{guild_id: guild_id} do
      FakeVoice.claim(guild_id)
      guild = %{id: guild_id, voice_states: [voice_state(guild_id, "777", "123")]}

      capture_log(fn ->
        with_mocks([cache(guild), bot(), chat()]) do
          Handler.handle_event({:MESSAGE_CREATE, command(guild_id, "!join"), nil})

          assert_received {:fake_voice, ^guild_id, {:join, "123"}}
          assert_received {:chat, "text", "Joined your voice channel!" <> _}
          assert AudioPlayer.current_voice_channel(guild_id) == {:ok, {guild_id, "123"}}

          Handler.handle_event({:MESSAGE_CREATE, command(guild_id, "!leave"), nil})

          assert_received {:fake_voice, ^guild_id, :leave}
          assert_received {:chat, "text", "Left the voice channel!"}
          assert AudioPlayer.current_voice_channel(guild_id) == {:ok, nil}
        end
      end)
    end

    test "!join and !leave say so when the bot could not move", %{guild_id: guild_id} do
      in_voice = %{id: guild_id, voice_states: [voice_state(guild_id, "777", "123")]}
      not_in_voice = %{id: guild_id, voice_states: []}
      join_failed = "I couldn't join your voice channel. Try again in a moment."
      leave_failed = "I couldn't leave the voice channel. Try again in a moment."

      table = [
        {"user is not in voice", "!join", not_in_voice, true, :ok,
         "You need to be in a voice channel!"},
        {"bot is not ready", "!join", in_voice, false, :ok, join_failed},
        {"Discord rejects the join", "!join", in_voice, true, {:error, :timeout}, join_failed},
        {"bot is not ready", "!leave", in_voice, false, :ok, leave_failed}
      ]

      for {label, content, guild, ready?, join_result, reply} <- table do
        FakeVoice.claim(guild_id, join: join_result)
        Application.put_env(:soundboard, :bot_ready, ready?)

        capture_log(fn ->
          with_mocks([cache(guild), bot(), chat()]) do
            Handler.handle_event({:MESSAGE_CREATE, command(guild_id, content), nil})
          end
        end)

        assert_received {:chat, "text", ^reply}, "#{content}: #{label}"
        assert AudioPlayer.current_voice_channel(guild_id) == {:ok, nil}, label
      end
    end
  end

  defp played_sounds(guild_id, mocks, fun) do
    test_pid = self()

    player =
      {AudioPlayer, [],
       [
         play_sound: fn filename, played_by, ^guild_id ->
           send(test_pid, {:player, {:play_sound, filename, played_by}})
           :ok
         end,
         last_user_left: fn guild ->
           send(test_pid, {:player, {:last_user_left, guild}})
           :ok
         end
       ]}

    capture_log(fn -> with_mocks([player, bot() | mocks], do: fun.()) end)
    collect_player_calls()
  end

  defp collect_player_calls do
    receive do
      {:player, call} -> [call | collect_player_calls()]
    after
      0 -> []
    end
  end

  defp cache(guild) do
    guild_id = guild.id
    {GuildCache, [], [all: fn -> [guild] end, get: fn ^guild_id -> {:ok, guild} end]}
  end

  defp bot, do: {BotIdentity, [], [fetch: fn -> {:ok, %{id: @bot_id}} end]}

  defp chat do
    test_pid = self()

    {Message, [],
     [
       create: fn channel_id, body ->
         send(test_pid, {:chat, channel_id, body})
         :ok
       end
     ]}
  end

  defp command(guild_id, content),
    do: %{content: content, guild_id: guild_id, channel_id: "text", author: %{id: "777"}}

  defp payload(guild_id, user_id, channel_id, session_id \\ "abc"),
    do: %{channel_id: channel_id, guild_id: guild_id, user_id: user_id, session_id: session_id}

  defp voice_state(guild_id, user_id, channel_id),
    do: %{user_id: user_id, channel_id: channel_id, guild_id: guild_id, session_id: "s"}

  defp join_sound!(user, guild_id) do
    sound = insert_sound!(user, %{filename: "join.mp3", guild_id: guild_id})
    insert_user_sound_setting!(user, sound, %{guild_id: guild_id, is_join_sound: true})
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
