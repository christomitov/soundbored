defmodule SoundboardWeb.AudioPlayerPipelineTest do
  use Soundboard.DataCase
  import Mock

  alias Soundboard.Accounts.{Tenants, User}
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
end
