defmodule Soundboard.AudioPlayerTest do
  use Soundboard.DataCase, async: false

  @moduletag :capture_log

  import Mock

  alias Soundboard.Accounts.User
  alias Soundboard.{AudioPlayer, FakeVoice, PubSubTopics, Sound}
  alias Soundboard.Discord.{GuildCache, Handler}
  alias Soundboard.Stats.Play

  @channel "voice-1"
  @not_connected "Bot is not connected to a voice channel. Use !join in Discord first."

  setup do
    on_exit(fn ->
      System.delete_env("AUTO_JOIN")
      System.delete_env("VOICE_IDLE_TIMEOUT_SECONDS")
      Application.put_env(:soundboard, :ffmpeg_executable, "ffmpeg")
    end)

    guild = new_guild()
    PubSubTopics.subscribe_playback(guild)
    %{user: insert_user!("player"), guild: guild}
  end

  describe "playback" do
    test "plays a guild sound through the voice connection", %{guild: guild, user: user} do
      sound = url_sound!(user, guild, %{volume: 0.8})
      FakeVoice.claim(guild, channel: @channel)
      connect(guild)

      AudioPlayer.play_sound(sound.filename, "System", guild)

      assert_receive {:fake_voice, ^guild, {:play, "https://sounds.example/" <> _, :url, opts}}
      assert opts == [volume: 0.8]
      assert_receive {:sound_played, %{filename: filename, played_by: "System"}}
      assert filename == sound.filename
    end

    test "a new play interrupts the sound that is still playing", %{guild: guild, user: user} do
      first = url_sound!(user, guild)
      second = url_sound!(user, guild)
      FakeVoice.claim(guild, channel: @channel, play: [:hold])
      connect(guild)

      AudioPlayer.play_sound(first.filename, "System", guild)
      assert_receive {:fake_voice_holding, ^guild, first_task}
      first_ref = Process.monitor(first_task)

      AudioPlayer.play_sound(second.filename, "System", guild)

      assert_receive {:fake_voice, ^guild, :stop}
      assert_receive {:DOWN, ^first_ref, :process, ^first_task, :killed}
      second_url = second.url
      assert_receive {:fake_voice, ^guild, {:play, ^second_url, :url, _}}
      assert_receive {:sound_played, %{filename: filename}}
      assert filename == second.filename
    end

    test "when EDA keeps playing after stop, VOICE_PLAYBACK_FINISHED starts the queued sound",
         %{guild: guild, user: user} do
      first = url_sound!(user, guild)
      second = url_sound!(user, guild)
      FakeVoice.claim(guild, channel: @channel, play: [:hold], stop: :ignored)
      connect(guild)

      AudioPlayer.play_sound(first.filename, "System", guild)
      assert_receive {:fake_voice_holding, ^guild, _first_task}

      AudioPlayer.play_sound(second.filename, "System", guild)
      assert_receive {:fake_voice, ^guild, :stop}

      second_url = second.url
      refute_receive {:fake_voice, ^guild, {:play, ^second_url, _, _}}, 100

      Handler.handle_event({:VOICE_PLAYBACK_FINISHED, %{guild_id: guild}, nil})

      assert_receive {:fake_voice, ^guild, {:play, ^second_url, :url, _}}, 300
    end

    test "stop_sound kills the playback in progress", %{guild: guild, user: user} do
      sound = url_sound!(user, guild)
      FakeVoice.claim(guild, channel: @channel, play: [:hold])
      connect(guild)

      AudioPlayer.play_sound(sound.filename, "System", guild)
      assert_receive {:fake_voice_holding, ^guild, task}
      ref = Process.monitor(task)

      AudioPlayer.stop_sound(guild)

      assert_receive {:fake_voice, ^guild, :stop}
      assert_receive {:DOWN, ^ref, :process, ^task, :killed}
      assert_receive {:sound_played, %{filename: "All sounds stopped", played_by: "System"}}
    end

    test "stop_sound without a voice channel reports that the bot is not connected",
         %{guild: guild} do
      FakeVoice.claim(guild)
      PubSubTopics.subscribe_playback(guild)

      AudioPlayer.stop_sound(guild)

      assert_receive {:error, "Bot is not connected to a voice channel"}
      refute_received {:fake_voice, ^guild, :stop}
    end

    test "two guilds play at once and stop independently", %{guild: guild_a, user: user} do
      guild_b = new_guild()
      sound_a = url_sound!(user, guild_a)
      sound_b = url_sound!(user, guild_b)
      FakeVoice.claim(guild_a, channel: @channel, play: [:hold])
      FakeVoice.claim(guild_b, channel: @channel, play: [:hold])
      connect(guild_a)
      connect(guild_b)

      AudioPlayer.play_sound(sound_a.filename, "System", guild_a)
      AudioPlayer.play_sound(sound_b.filename, "System", guild_b)
      assert_receive {:fake_voice_holding, ^guild_a, task_a}
      assert_receive {:fake_voice_holding, ^guild_b, task_b}
      ref_a = Process.monitor(task_a)

      AudioPlayer.stop_sound(guild_a)

      assert_receive {:DOWN, ^ref_a, :process, ^task_a, :killed}
      assert Process.alive?(task_b)
      refute_received {:fake_voice, ^guild_b, :stop}
    end

    test "unplayable sounds report why and never reach voice", %{guild: guild, user: user} do
      missing_file = insert_sound!(user, %{guild_id: guild, source_type: "local"})
      FakeVoice.claim(guild, channel: @channel)
      connect(guild)

      AudioPlayer.play_sound(missing_file.filename, "System", guild)
      AudioPlayer.play_sound("never-uploaded.mp3", "System", guild)

      expected_path = Soundboard.UploadsPath.file_path(missing_file.storage_key)
      assert_receive {:error, "Sound file not found at " <> path}
      assert path == expected_path
      assert_receive {:error, "Sound not found"}
      refute_received {:fake_voice, ^guild, {:play, _, _, _}}
    end

    test "a play that voice rejects is reported to the guild", %{guild: guild, user: user} do
      sound = url_sound!(user, guild)
      FakeVoice.claim(guild, channel: @channel, play: [{:error, :boom}])
      connect(guild)

      AudioPlayer.play_sound(sound.filename, user, guild)

      assert_receive {:error, "Failed to play sound: :boom"}
      refute_received {:sound_played, _}
      refute Repo.get_by(Play, user_id: user.id)
    end

    test "without ffmpeg the guild sees an error and voice is never asked to play",
         %{guild: guild, user: user} do
      Application.put_env(:soundboard, :ffmpeg_executable, false)
      sound = url_sound!(user, guild)
      FakeVoice.claim(guild, channel: @channel)
      connect(guild)

      AudioPlayer.play_sound(sound.filename, "System", guild)

      assert_receive {:error, "ffmpeg is not installed on this host"}
      refute_received {:fake_voice, ^guild, {:play, _, _, _}}
    end

    test "plays by a signed-in user are recorded in stats, other actors are not",
         %{guild: guild, user: user} do
      sound = url_sound!(user, guild)
      FakeVoice.claim(guild, channel: @channel)
      connect(guild)

      AudioPlayer.play_sound(sound.filename, user, guild)
      assert_receive {:sound_played, %{played_by: "player"}}

      AudioPlayer.play_sound(sound.filename, "nobody-by-this-name", guild)
      assert_receive {:sound_played, %{played_by: "nobody-by-this-name"}}

      AudioPlayer.play_sound(sound.filename, "System", guild)
      assert_receive {:sound_played, %{played_by: "System"}}

      assert [%Play{user_id: user_id}] = Repo.all(from p in Play, where: p.sound_id == ^sound.id)
      assert user_id == user.id
    end
  end

  describe "auto-join on play" do
    test "joins the player's voice channel when the bot has none", %{guild: guild, user: user} do
      sound = url_sound!(user, guild)
      FakeVoice.claim(guild)
      cached = [%{id: guild, voice_states: [%{user_id: user.discord_id, channel_id: "ch-5"}]}]

      with_mock GuildCache, all: fn -> cached end do
        AudioPlayer.play_sound(sound.filename, user, guild)

        assert_receive {:fake_voice, ^guild, {:join, "ch-5"}}
        assert_receive {:fake_voice, ^guild, {:play, _, :url, _}}
        assert AudioPlayer.current_voice_channel(guild) == {:ok, {guild, "ch-5"}}
        assert armed?(guild)
      end
    end

    test "reports that the bot is not connected when it cannot auto-join",
         %{guild: guild, user: user} do
      sound = url_sound!(user, guild)
      FakeVoice.claim(guild)
      in_voice = [%{id: guild, voice_states: [%{user_id: user.discord_id, channel_id: "ch-5"}]}]

      elsewhere = [
        %{id: "another-guild", voice_states: [%{user_id: user.discord_id, channel_id: "ch-5"}]}
      ]

      table = [
        {"player is in no voice channel here", :play, elsewhere, user},
        {"actor has no Discord account", :play, in_voice, "System"},
        {"auto-join is off", false, in_voice, user},
        {"guild cache is down", :play, :raise, user}
      ]

      for {label, mode, cache, actor} <- table do
        auto_join(mode)

        with_mock GuildCache,
          all: fn -> if cache == :raise, do: raise("cache down"), else: cache end do
          AudioPlayer.play_sound(sound.filename, actor, guild)

          assert_receive {:error, @not_connected}, 500, label
          refute_received {:fake_voice, ^guild, {:join, _}}, label
          assert AudioPlayer.current_voice_channel(guild) == {:ok, nil}, label
        end
      end
    end
  end

  describe "idle timeout" do
    test "joining in play mode leaves the channel once the idle timeout passes", %{guild: guild} do
      System.put_env("VOICE_IDLE_TIMEOUT_SECONDS", "1")
      FakeVoice.claim(guild, channel: @channel)

      connect(guild)

      assert_receive {:fake_voice, ^guild, :leave}, 2_000
      assert AudioPlayer.current_voice_channel(guild) == {:ok, nil}
    end

    test "presence and false modes do not arm the idle timer on join", %{guild: guild} do
      for mode <- [:presence, false] do
        auto_join(mode)
        AudioPlayer.set_voice_channel(guild, nil)

        connect(guild)

        assert AudioPlayer.current_voice_channel(guild) == {:ok, {guild, @channel}}
        refute armed?(guild), "#{mode} mode armed the idle timer"
      end
    end

    test "clearing the voice channel cancels the idle timer", %{guild: guild} do
      connect(guild)
      assert armed?(guild)

      AudioPlayer.set_voice_channel(guild, nil)

      assert AudioPlayer.current_voice_channel(guild) == {:ok, nil}
      refute armed?(guild)
    end

    test "playing a sound restarts the idle timer", %{guild: guild, user: user} do
      sound = url_sound!(user, guild)
      FakeVoice.claim(guild, channel: @channel)
      connect(guild)
      before = idle_timer(guild)

      AudioPlayer.play_sound(sound.filename, "System", guild)
      assert_receive {:fake_voice, ^guild, {:play, _, _, _}}

      assert idle_timer(guild) not in [nil, before]
    end

    test "a stale idle timeout message does not make the bot leave", %{guild: guild} do
      FakeVoice.claim(guild, channel: @channel)
      connect(guild)

      send(AudioPlayer.server_pid(guild), {:idle_timeout, make_ref()})

      assert AudioPlayer.current_voice_channel(guild) == {:ok, {guild, @channel}}
      refute_received {:fake_voice, ^guild, :leave}
    end
  end

  describe "last_user_left" do
    test "play and presence modes leave at once", %{guild: guild} do
      FakeVoice.claim(guild, channel: @channel)

      for mode <- [:play, :presence] do
        auto_join(mode)
        connect(guild)

        AudioPlayer.last_user_left(guild)

        assert_receive {:fake_voice, ^guild, :leave}
        assert AudioPlayer.current_voice_channel(guild) == {:ok, nil}
        refute armed?(guild)
      end
    end

    test "false mode stays and arms the idle timer only when one is configured",
         %{guild: guild} do
      FakeVoice.claim(guild, channel: @channel)
      auto_join(false)

      for {timeout, armed} <- [{"60", true}, {"0", false}] do
        System.put_env("VOICE_IDLE_TIMEOUT_SECONDS", timeout)
        connect(guild)

        AudioPlayer.last_user_left(guild)

        assert AudioPlayer.current_voice_channel(guild) == {:ok, {guild, @channel}}
        assert armed?(guild) == armed
        refute_received {:fake_voice, ^guild, :leave}
      end
    end

    test "is ignored when the bot is not in a channel", %{guild: guild} do
      FakeVoice.claim(guild)
      AudioPlayer.ensure_started(guild)

      AudioPlayer.last_user_left(guild)

      assert AudioPlayer.current_voice_channel(guild) == {:ok, nil}
      refute_received {:fake_voice, ^guild, :leave}
    end

    test "a user joining the bot's channel cancels the false-mode idle timer", %{guild: guild} do
      auto_join(false)
      connect(guild)
      AudioPlayer.last_user_left(guild)
      assert armed?(guild)

      AudioPlayer.user_joined_channel(guild)

      refute armed?(guild)
    end
  end

  describe "voice maintenance" do
    test "rejoins when EDA lost the channel or the session is stale, even if status calls raise" do
      lost = new_guild()
      stale = new_guild()
      FakeVoice.claim(lost, channel: nil, ready: false)
      FakeVoice.claim(stale, channel: @channel, ready: false, playing: :raise)
      connect(lost)
      connect(stale)

      send(AudioPlayer.server_pid(lost), :check_voice_connection)
      send(AudioPlayer.server_pid(stale), :check_voice_connection)

      for guild <- [lost, stale] do
        assert_receive {:fake_voice, ^guild, :leave}
        assert_receive {:fake_voice, ^guild, {:join, @channel}}, 2_000
        assert AudioPlayer.current_voice_channel(guild) == {:ok, {guild, @channel}}
      end
    end
  end

  defp new_guild do
    guild = "guild-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      if pid = AudioPlayer.server_pid(guild), do: GenServer.stop(pid)
    end)

    guild
  end

  defp connect(guild) do
    AudioPlayer.set_voice_channel(guild, @channel)
    {:ok, {^guild, @channel}} = AudioPlayer.current_voice_channel(guild)
  end

  defp auto_join(:play), do: System.delete_env("AUTO_JOIN")
  defp auto_join(mode), do: System.put_env("AUTO_JOIN", to_string(mode))

  defp idle_timer(guild) do
    case :sys.get_state(AudioPlayer.server_pid(guild)).idle_timeout_ref do
      {_timer, token} -> token
      nil -> nil
    end
  end

  defp armed?(guild), do: idle_timer(guild) != nil

  defp insert_user!(username) do
    %User{}
    |> User.changeset(%{
      username: username,
      discord_id: Integer.to_string(System.unique_integer([:positive])),
      avatar: "avatar.png"
    })
    |> Repo.insert!()
  end

  defp url_sound!(user, guild, attrs \\ %{}) do
    name = "sound-#{System.unique_integer([:positive])}.mp3"

    insert_sound!(
      user,
      Map.merge(
        %{guild_id: guild, source_type: "url", url: "https://sounds.example/#{name}"},
        attrs
      )
    )
  end

  defp insert_sound!(user, attrs) do
    attrs =
      Map.merge(
        %{filename: "sound-#{System.unique_integer([:positive])}.mp3", user_id: user.id},
        attrs
      )

    %Sound{}
    |> Sound.changeset(attrs)
    |> Repo.insert!()
  end
end
