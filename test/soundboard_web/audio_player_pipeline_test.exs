defmodule SoundboardWeb.AudioPlayerPipelineTest do
  use Soundboard.DataCase
  import Mock

  alias Soundboard.Accounts.Tenants
  alias Soundboard.Accounts.User
  alias Soundboard.{PubSubTopics, Repo, Sound}
  alias SoundboardWeb.AudioPlayer

  setup do
    tenant = Tenants.ensure_default_tenant!()

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "player",
        discord_id: "discord-player",
        avatar: "avatar.png",
        tenant_id: tenant.id
      })
      |> Repo.insert()

    uploads_dir = Path.join(:code.priv_dir(:soundboard), "static/uploads")
    File.mkdir_p!(uploads_dir)
    filepath = Path.join(uploads_dir, "pipeline.mp3")
    File.write!(filepath, "audio-bytes")

    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "pipeline.mp3",
        source_type: "local",
        user_id: user.id,
        tenant_id: tenant.id
      })
      |> Repo.insert()

    on_exit(fn -> File.rm_rf(filepath) end)

    # Ensure the player has a voice target
    AudioPlayer.set_voice_channel(123, 456)

    {:ok, tenant: tenant, user: user, sound: sound}
  end

  test "play_sound broadcasts success when voice is ready", %{
    tenant: tenant,
    user: user,
    sound: sound
  } do
    Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(tenant.id))

    parent = self()

    with_mocks([
      {Nostrum.Voice, [],
       [
         ready?: fn _ -> true end,
         playing?: fn _ -> false end,
         play: fn guild_id, _input, _type, _opts ->
           send(parent, {:played, guild_id})
           :ok
         end,
         stop: fn _ -> :ok end
       ]}
    ]) do
      AudioPlayer.play_sound(sound.filename, user.username)

      assert_receive {:played, 123}

      assert_receive {:sound_played,
                      %{filename: "pipeline.mp3", played_by: "player", tenant_id: tenant_id}},
                     200

      assert tenant_id == tenant.id
    end
  end

  test "play_sound broadcasts error when voice join fails", %{tenant: tenant, sound: sound} do
    Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(tenant.id))

    with_mocks([
      {Nostrum.Voice, [],
       [
         ready?: fn _ -> false end,
         join_channel: fn _, _ -> raise "join failed" end,
         playing?: fn _ -> false end
       ]}
    ]) do
      AudioPlayer.play_sound(sound.filename, "missing-user")
      assert_receive {:error, "Failed to connect to voice channel"}, 200
    end
  end

  test "play_sound without a voice channel emits error broadcast", %{tenant: tenant, sound: sound} do
    Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(tenant.id))

    # Clear the voice channel so the guard path triggers
    AudioPlayer.set_voice_channel(nil, nil)

    AudioPlayer.play_sound(sound.filename, "anyone")

    assert_receive {:error,
                    "Bot is not connected to a voice channel. Use !join in Discord first."},
                   200
  end

  describe "play_url/3" do
    test "broadcasts success with default parameters when voice is ready", %{tenant: tenant} do
      Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(tenant.id))

      parent = self()

      with_mocks([
        {Nostrum.Voice, [],
         [
           ready?: fn _ -> true end,
           playing?: fn _ -> false end,
           play: fn guild_id, _input, _type, opts ->
             send(parent, {:played, guild_id, opts})
             :ok
           end,
           stop: fn _ -> :ok end
         ]}
      ]) do
        AudioPlayer.play_url("http://example.com/stream.mp3")

        assert_receive {:played, 123, opts}, 200
        assert Keyword.get(opts, :volume) == 1.0
        assert Keyword.get(opts, :realtime) == false

        assert_receive {:sound_played,
                        %{filename: "streamed_audio", played_by: "API User", tenant_id: _}},
                       200
      end
    end

    test "broadcasts success with custom volume and username", %{tenant: tenant} do
      Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(tenant.id))

      parent = self()

      with_mocks([
        {Nostrum.Voice, [],
         [
           ready?: fn _ -> true end,
           playing?: fn _ -> false end,
           play: fn guild_id, _input, _type, opts ->
             send(parent, {:played, guild_id, opts})
             :ok
           end,
           stop: fn _ -> :ok end
         ]}
      ]) do
        AudioPlayer.play_url("http://example.com/stream.mp3", 0.5, "CustomUser")

        assert_receive {:played, 123, opts}, 200
        assert Keyword.get(opts, :volume) == 0.5

        assert_receive {:sound_played,
                        %{filename: "streamed_audio", played_by: "CustomUser", tenant_id: _}},
                       200
      end
    end

    test "broadcasts error when no voice channel is set" do
      AudioPlayer.set_voice_channel(nil, nil)

      # Subscribe to default tenant topic
      tenant = Tenants.ensure_default_tenant!()
      Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(tenant.id))

      AudioPlayer.play_url("http://example.com/stream.mp3")

      assert_receive {:error,
                      "Bot is not connected to a voice channel. Use !join in Discord first."},
                     200
    end

    test "broadcasts error when voice play fails", %{tenant: tenant} do
      Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(tenant.id))

      with_mocks([
        {Nostrum.Voice, [],
         [
           ready?: fn _ -> true end,
           playing?: fn _ -> false end,
           play: fn _guild_id, _input, _type, _opts ->
             {:error, "Connection lost"}
           end,
           stop: fn _ -> :ok end
         ]}
      ]) do
        AudioPlayer.play_url("http://example.com/stream.mp3")

        assert_receive {:error, "Failed to play audio: Connection lost"}, 200
      end
    end
  end

  describe "volume clamping via play_url/3" do
    test "clamps volume below 0 to 0.0", %{tenant: tenant} do
      Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(tenant.id))

      parent = self()

      with_mocks([
        {Nostrum.Voice, [],
         [
           ready?: fn _ -> true end,
           playing?: fn _ -> false end,
           play: fn _guild_id, _input, _type, opts ->
             send(parent, {:volume, Keyword.get(opts, :volume)})
             :ok
           end,
           stop: fn _ -> :ok end
         ]}
      ]) do
        AudioPlayer.play_url("http://example.com/stream.mp3", -0.5)

        assert_receive {:volume, volume}, 200
        assert volume == +0.0
      end
    end

    test "clamps volume above 1 to 1.0", %{tenant: tenant} do
      Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(tenant.id))

      parent = self()

      with_mocks([
        {Nostrum.Voice, [],
         [
           ready?: fn _ -> true end,
           playing?: fn _ -> false end,
           play: fn _guild_id, _input, _type, opts ->
             send(parent, {:volume, Keyword.get(opts, :volume)})
             :ok
           end,
           stop: fn _ -> :ok end
         ]}
      ]) do
        AudioPlayer.play_url("http://example.com/stream.mp3", 1.5)

        assert_receive {:volume, 1.0}, 200
      end
    end

    test "keeps volume within valid range unchanged", %{tenant: tenant} do
      Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(tenant.id))

      parent = self()

      with_mocks([
        {Nostrum.Voice, [],
         [
           ready?: fn _ -> true end,
           playing?: fn _ -> false end,
           play: fn _guild_id, _input, _type, opts ->
             send(parent, {:volume, Keyword.get(opts, :volume)})
             :ok
           end,
           stop: fn _ -> :ok end
         ]}
      ]) do
        AudioPlayer.play_url("http://example.com/stream.mp3", 0.75)

        assert_receive {:volume, 0.75}, 200
      end
    end

    test "defaults non-numeric volume to 1.0", %{tenant: tenant} do
      Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(tenant.id))

      parent = self()

      with_mocks([
        {Nostrum.Voice, [],
         [
           ready?: fn _ -> true end,
           playing?: fn _ -> false end,
           play: fn _guild_id, _input, _type, opts ->
             send(parent, {:volume, Keyword.get(opts, :volume)})
             :ok
           end,
           stop: fn _ -> :ok end
         ]}
      ]) do
        AudioPlayer.play_url("http://example.com/stream.mp3", "invalid")

        assert_receive {:volume, 1.0}, 200
      end
    end
  end
end
