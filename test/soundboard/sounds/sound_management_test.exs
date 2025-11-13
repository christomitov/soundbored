defmodule Soundboard.Sounds.SoundManagementTest do
  use Soundboard.DataCase
  alias Soundboard.{Accounts.User, Repo, Sound}
  alias Soundboard.Accounts.Tenants

  describe "sound management" do
    setup do
      user = insert_user()
      {:ok, sound} = insert_sound(user)
      %{user: user, sound: sound}
    end

    test "can rename sound", %{sound: sound} do
      {:ok, updated_sound} =
        Sound.changeset(sound, %{filename: "renamed_sound.mp3"})
        |> Repo.update()

      assert updated_sound.filename == "renamed_sound.mp3"
      assert updated_sound.id == sound.id
    end

    test "prevents duplicate filenames", %{user: user} do
      {:ok, _sound1} = insert_sound(user, %{filename: "test_sound1.mp3"})
      {:ok, sound2} = insert_sound(user, %{filename: "test_sound2.mp3"})

      result =
        Sound.changeset(sound2, %{filename: "test_sound1.mp3"})
        |> Repo.update()

      assert {:error, changeset} = result
      assert "has already been taken" in errors_on(changeset).filename
    end

    test "owner can delete sound", %{sound: sound} do
      assert {:ok, _} = Repo.delete(sound)
      refute Repo.get(Sound, sound.id)
    end
  end

  # Helper functions
  defp insert_user(attrs \\ %{}) do
    tenant = Tenants.ensure_default_tenant!()

    {:ok, user} =
      %Soundboard.Accounts.User{}
      |> User.changeset(
        Map.merge(
          %{
            username: "testuser",
            discord_id: "123456789",
            avatar: "test_avatar.jpg",
            tenant_id: tenant.id
          },
          attrs
        )
      )
      |> Repo.insert()

    user
  end

  defp insert_sound(user, attrs \\ %{}) do
    %Soundboard.Sound{}
    |> Sound.changeset(
      Map.merge(
        %{
          filename: "test_sound#{System.unique_integer()}.mp3",
          source_type: "local",
          user_id: user.id
        },
        attrs
      )
    )
    |> Repo.insert()
  end
end
