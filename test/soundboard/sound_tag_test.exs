defmodule Soundboard.SoundTagTest do
  @moduledoc """
  Test for the SoundTag module.
  """
  use Soundboard.DataCase
  alias Soundboard.Accounts.{Tenants, User}
  alias Soundboard.{Sound, SoundTag, Tag}

  describe "sound_tags" do
    test "changeset with valid attributes" do
      sound = insert_sound()
      tag = insert_tag()

      attrs = %{
        sound_id: sound.id,
        tag_id: tag.id,
        tenant_id: sound.tenant_id
      }

      changeset = SoundTag.changeset(%SoundTag{}, attrs)
      assert changeset.valid?
      assert {:ok, sound_tag} = Repo.insert(changeset)
      assert sound_tag.sound_id == sound.id
      assert sound_tag.tag_id == tag.id
    end

    test "changeset enforces unique constraint" do
      sound = insert_sound()
      tag = insert_tag()
      attrs = %{sound_id: sound.id, tag_id: tag.id, tenant_id: sound.tenant_id}

      # First insert succeeds
      {:ok, _} = Repo.insert(SoundTag.changeset(%SoundTag{}, attrs))

      # Second insert fails
      changeset = SoundTag.changeset(%SoundTag{}, attrs)
      {:error, changeset} = Repo.insert(changeset)

      # Check the error on the composite unique index
      assert {"has already been taken", _} = changeset.errors[:sound_id]
    end

    test "changeset requires sound_id and tag_id" do
      changeset = SoundTag.changeset(%SoundTag{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).sound_id
      assert "can't be blank" in errors_on(changeset).tag_id
      assert "can't be blank" in errors_on(changeset).tenant_id
    end
  end

  # Helper functions
  defp insert_sound do
    user = insert_user()

    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "test_sound#{System.unique_integer()}.mp3",
        source_type: "local",
        user_id: user.id,
        tenant_id: user.tenant_id
      })
      |> Repo.insert()

    sound
  end

  defp insert_tag do
    tenant = Tenants.ensure_default_tenant!()

    {:ok, tag} =
      %Tag{}
      |> Tag.changeset(%{name: "test_tag#{System.unique_integer()}", tenant_id: tenant.id})
      |> Repo.insert()

    tag
  end

  defp insert_user do
    tenant = Tenants.ensure_default_tenant!()

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser#{System.unique_integer()}",
        discord_id: "123456789",
        avatar: "test_avatar.jpg",
        tenant_id: tenant.id
      })
      |> Repo.insert()

    user
  end
end
