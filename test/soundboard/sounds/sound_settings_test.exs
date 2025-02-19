defmodule Soundboard.Sounds.SoundSettingsTest do
  use Soundboard.DataCase
  alias Soundboard.{UserSoundSetting, Sound, Accounts.User, Repo}
  import Ecto.Changeset

  setup do
    user = insert_user()
    {:ok, sound} = insert_sound(user)
    %{user: user, sound: sound}
  end

  describe "changeset validation" do
    test "requires user_id and sound_id" do
      changeset = UserSoundSetting.changeset(%UserSoundSetting{}, %{})

      assert errors_on(changeset) == %{
               user_id: ["can't be blank"],
               sound_id: ["can't be blank"]
             }
    end

    test "defaults join and leave sounds to false", %{user: user, sound: sound} do
      attrs = %{
        user_id: user.id,
        sound_id: sound.id
      }

      changeset = UserSoundSetting.changeset(%UserSoundSetting{}, attrs)
      assert get_field(changeset, :is_join_sound) == false
      assert get_field(changeset, :is_leave_sound) == false
    end

    test "accepts join and leave sound settings", %{user: user, sound: sound} do
      attrs = %{
        user_id: user.id,
        sound_id: sound.id,
        is_join_sound: true,
        is_leave_sound: false
      }

      changeset = UserSoundSetting.changeset(%UserSoundSetting{}, attrs)
      assert get_field(changeset, :is_join_sound) == true
      assert get_field(changeset, :is_leave_sound) == false
    end
  end

  describe "unique constraints" do
    test "enforces unique join sound per user", %{user: user, sound: sound} do
      # First insert succeeds
      {:ok, _} =
        %UserSoundSetting{
          user_id: user.id,
          sound_id: sound.id,
          is_join_sound: true
        }
        |> Repo.insert()

      # Second insert should fail with constraint error
      changeset =
        %UserSoundSetting{}
        |> UserSoundSetting.changeset(%{
          user_id: user.id,
          sound_id: sound.id,
          is_join_sound: true
        })
        |> unique_constraint(:user_id,
          name: "user_sound_settings_user_id_is_join_sound_index",
          message: "already has a join sound"
        )

      {:error, changeset} = Repo.insert(changeset)
      assert %{user_id: ["already has a join sound"]} = errors_on(changeset)
    end

    test "enforces unique leave sound per user", %{user: user, sound: sound} do
      # First insert succeeds
      {:ok, _} =
        %UserSoundSetting{
          user_id: user.id,
          sound_id: sound.id,
          is_leave_sound: true
        }
        |> Repo.insert()

      # Second insert should fail with constraint error
      changeset =
        %UserSoundSetting{}
        |> UserSoundSetting.changeset(%{
          user_id: user.id,
          sound_id: sound.id,
          is_leave_sound: true
        })
        |> unique_constraint(:user_id,
          name: "user_sound_settings_user_id_is_leave_sound_index",
          message: "already has a leave sound"
        )

      {:error, changeset} = Repo.insert(changeset)
      assert %{user_id: ["already has a leave sound"]} = errors_on(changeset)
    end
  end

  # Helper functions
  defp insert_user do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "test_user",
        discord_id: "123456",
        avatar: "test.jpg"
      })
      |> Repo.insert()

    user
  end

  defp insert_sound(user) do
    %Sound{}
    |> Sound.changeset(%{
      filename: "test_sound#{System.unique_integer()}.mp3",
      source_type: "local",
      user_id: user.id
    })
    |> Repo.insert()
  end
end
