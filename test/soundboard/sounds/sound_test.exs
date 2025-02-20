defmodule Soundboard.Sounds.SoundTest do
  @moduledoc """
  Tests the Sound module.
  """
  use Soundboard.DataCase
  alias Soundboard.Accounts.User
  alias Soundboard.{Repo, Sound, Tag, UserSoundSetting}

  describe "changeset validation" do
    test "validates required fields" do
      changeset = Sound.changeset(%Sound{}, %{})

      assert errors_on(changeset) == %{
               filename: ["can't be blank"],
               user_id: ["can't be blank"]
             }
    end

    test "validates local sound requires filename" do
      changeset =
        Sound.changeset(%Sound{}, %{
          user_id: 1,
          source_type: "local"
        })

      assert "can't be blank" in errors_on(changeset).filename
    end

    test "validates url sound requires url" do
      changeset =
        Sound.changeset(%Sound{}, %{
          user_id: 1,
          source_type: "url"
        })

      assert "can't be blank" in errors_on(changeset).url
    end

    test "validates source type values" do
      changeset =
        Sound.changeset(%Sound{}, %{
          user_id: 1,
          source_type: "invalid"
        })

      assert "must be either 'local' or 'url'" in errors_on(changeset).source_type
    end

    test "enforces unique filenames" do
      user = insert_user()
      attrs = %{filename: "test.mp3", source_type: "local", user_id: user.id}

      {:ok, _} = %Sound{} |> Sound.changeset(attrs) |> Repo.insert()
      {:error, changeset} = %Sound{} |> Sound.changeset(attrs) |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).filename
    end
  end

  setup do
    user = insert_user()
    {:ok, tag} = %Tag{name: "test_tag"} |> Tag.changeset(%{}) |> Repo.insert()
    {:ok, sound} = insert_sound(user)
    %{user: user, sound: sound, tag: tag}
  end

  describe "tag associations" do
    test "can associate tags through changeset", %{user: user, tag: tag} do
      attrs = %{
        filename: "test_sound_new.mp3",
        source_type: "local",
        user_id: user.id
      }

      {:ok, sound} =
        %Sound{}
        |> Sound.changeset(attrs)
        |> Repo.insert()

      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
        [sound.id, tag.id, now, now]
      )

      sound = Repo.preload(sound, :tags)
      assert [%{name: "test_tag"}] = sound.tags
    end
  end

  describe "queries" do
    test "with_tags/1 preloads tags", %{sound: sound, tag: tag} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
        [sound.id, tag.id, now, now]
      )

      result = Sound.with_tags() |> Repo.all() |> Enum.find(&(&1.id == sound.id))
      assert [%{name: "test_tag"}] = result.tags
    end

    test "by_tag/2 filters sounds by tag name", %{sound: sound, tag: tag} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
        [sound.id, tag.id, now, now]
      )

      results = Sound.by_tag("test_tag") |> Repo.all()
      assert length(results) == 1
      assert hd(results).id == sound.id
    end

    test "list_files/0 returns all sounds with tags and settings", %{sound: sound, tag: tag} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
        [sound.id, tag.id, now, now]
      )

      result = Sound.list_files() |> Enum.find(&(&1.id == sound.id))
      assert result.id == sound.id
      assert [%{name: "test_tag"}] = result.tags
    end

    test "get_sound!/1 loads all associations", %{sound: sound, tag: tag} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
        [sound.id, tag.id, now, now]
      )

      result = Sound.get_sound!(sound.id)
      assert result.id == sound.id
      assert [%{name: "test_tag"}] = result.tags
    end
  end

  describe "user sound settings" do
    test "can set join sound without affecting leave sound", %{user: user} do
      # Create two sounds
      {:ok, sound1} = insert_sound(user)
      {:ok, sound2} = insert_sound(user)

      # Set sound1 as both join and leave sound
      {:ok, setting1} =
        UserSoundSetting.changeset(
          %UserSoundSetting{},
          %{
            user_id: user.id,
            sound_id: sound1.id,
            is_join_sound: true,
            is_leave_sound: true
          }
        )
        |> Repo.insert()

      # Set sound2 as join sound (should only unset sound1's join sound)
      {:ok, setting2} =
        UserSoundSetting.changeset(
          %UserSoundSetting{},
          %{
            user_id: user.id,
            sound_id: sound2.id,
            is_join_sound: true,
            is_leave_sound: false
          }
        )
        |> Repo.insert()

      # Reload settings to verify state
      setting1 = Repo.get(UserSoundSetting, setting1.id)
      setting2 = Repo.get(UserSoundSetting, setting2.id)

      # Original sound should keep leave sound but lose join sound
      assert setting1.is_join_sound == false
      assert setting1.is_leave_sound == true

      # New sound should be join sound only
      assert setting2.is_join_sound == true
      assert setting2.is_leave_sound == false
    end

    test "can set leave sound without affecting join sound", %{user: user} do
      # Create two sounds
      {:ok, sound1} = insert_sound(user)
      {:ok, sound2} = insert_sound(user)

      # Set sound1 as both join and leave sound
      {:ok, setting1} =
        UserSoundSetting.changeset(
          %UserSoundSetting{},
          %{
            user_id: user.id,
            sound_id: sound1.id,
            is_join_sound: true,
            is_leave_sound: true
          }
        )
        |> Repo.insert()

      # Set sound2 as leave sound (should only unset sound1's leave sound)
      {:ok, setting2} =
        UserSoundSetting.changeset(
          %UserSoundSetting{},
          %{
            user_id: user.id,
            sound_id: sound2.id,
            is_join_sound: false,
            is_leave_sound: true
          }
        )
        |> Repo.insert()

      # Reload settings to verify state
      setting1 = Repo.get(UserSoundSetting, setting1.id)
      setting2 = Repo.get(UserSoundSetting, setting2.id)

      # Original sound should keep join sound but lose leave sound
      assert setting1.is_join_sound == true
      assert setting1.is_leave_sound == false

      # New sound should be leave sound only
      assert setting2.is_join_sound == false
      assert setting2.is_leave_sound == true
    end

    test "can unset join/leave sounds independently", %{user: user} do
      # Create a sound
      {:ok, sound} = insert_sound(user)

      # Set both join and leave
      {:ok, setting} =
        UserSoundSetting.changeset(
          %UserSoundSetting{},
          %{
            user_id: user.id,
            sound_id: sound.id,
            is_join_sound: true,
            is_leave_sound: true
          }
        )
        |> Repo.insert()

      # Unset join sound only
      {:ok, updated_setting} =
        UserSoundSetting.changeset(
          setting,
          %{is_join_sound: false}
        )
        |> Repo.update()

      # Verify leave sound remains set
      assert updated_setting.is_join_sound == false
      assert updated_setting.is_leave_sound == true
    end
  end

  # Helper functions
  defp insert_user do
    {:ok, user} =
      %Soundboard.Accounts.User{}
      |> User.changeset(%{
        username: "test_user_#{System.unique_integer()}",
        discord_id: "123456_#{System.unique_integer()}",
        avatar: "test.jpg"
      })
      |> Repo.insert()

    user
  end

  defp insert_sound(user) do
    %Sound{}
    |> Sound.changeset(%{
      filename: "test_sound_#{System.unique_integer()}.mp3",
      source_type: "local",
      user_id: user.id
    })
    |> Repo.insert()
  end
end
