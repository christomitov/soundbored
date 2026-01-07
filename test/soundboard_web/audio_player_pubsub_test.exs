defmodule SoundboardWeb.AudioPlayerPubSubTest do
  use Soundboard.DataCase, async: false

  alias Soundboard.{PubSubTopics, Repo, Sound}
  alias Soundboard.Accounts.{Tenant, Tenants, User}

  setup do
    default_tenant = Tenants.ensure_default_tenant!()

    {:ok, other_tenant} =
      %Tenant{}
      |> Tenant.changeset(%{name: "Other", slug: "other-tenant", plan: :pro})
      |> Repo.insert()

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "tenant_user",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png",
        tenant_id: other_tenant.id
      })
      |> Repo.insert()

    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "tenant-sound-#{System.unique_integer([:positive])}.mp3",
        source_type: "local",
        user_id: user.id,
        tenant_id: other_tenant.id
      })
      |> Repo.insert()

    {:ok, default_tenant: default_tenant, other_tenant: other_tenant, sound: sound}
  end

  test "stop_sound error broadcasts only to the caller's tenant topic", %{
    default_tenant: default_tenant,
    other_tenant: other_tenant
  } do
    Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(other_tenant.id))
    Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(default_tenant.id))

    SoundboardWeb.AudioPlayer.stop_sound(other_tenant.id)

    assert_receive {:error, _}, 200
    refute_receive {:error, _}, 50
  end

  test "play_sound error broadcasts stay scoped to the sound tenant", %{
    default_tenant: default_tenant,
    other_tenant: other_tenant,
    sound: sound
  } do
    Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(other_tenant.id))
    Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(default_tenant.id))

    SoundboardWeb.AudioPlayer.play_sound(sound.filename, "Tester")

    assert_receive {:error, _}, 200
    refute_receive {:error, _}, 50
  end
end
