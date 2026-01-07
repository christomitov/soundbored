defmodule Soundboard.Sounds.SoundTest do
  @moduledoc """
  Tests the Sound module.
  """
  use Soundboard.DataCase
  alias Soundboard.Accounts.{Tenant, Tenants, User}
  alias Soundboard.{Repo, Sound, Tag, UserSoundSetting}

  describe "changeset validation" do
    test "validates required fields" do
      changeset = Sound.changeset(%Sound{}, %{})

      assert errors_on(changeset) == %{
               filename: ["can't be blank"],
               tenant_id: ["can't be blank"],
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

    test "validates volume between 0 and 1.5" do
      user = insert_user()

      high_changeset =
        Sound.changeset(%Sound{}, %{
          filename: "loud.mp3",
          source_type: "local",
          user_id: user.id,
          volume: 1.6
        })

      assert Enum.any?(
               errors_on(high_changeset).volume,
               &String.contains?(&1, "less than or equal")
             )

      low_changeset =
        Sound.changeset(%Sound{}, %{
          filename: "quiet.mp3",
          source_type: "local",
          user_id: user.id,
          volume: -0.1
        })

      assert Enum.any?(
               errors_on(low_changeset).volume,
               &String.contains?(&1, "greater than or equal")
             )
    end
  end

  setup do
    user = insert_user()

    {:ok, tag} =
      %Tag{}
      |> Tag.changeset(%{name: "test_tag", tenant_id: user.tenant_id})
      |> Repo.insert()

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
        "INSERT INTO sound_tags (sound_id, tag_id, tenant_id, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        [sound.id, tag.id, sound.tenant_id, now, now]
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
        "INSERT INTO sound_tags (sound_id, tag_id, tenant_id, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        [sound.id, tag.id, sound.tenant_id, now, now]
      )

      result = Sound.with_tags() |> Repo.all() |> Enum.find(&(&1.id == sound.id))
      assert [%{name: "test_tag"}] = result.tags
    end

    test "by_tag/2 filters sounds by tag name", %{sound: sound, tag: tag} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, tenant_id, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        [sound.id, tag.id, sound.tenant_id, now, now]
      )

      results = Sound.by_tag("test_tag") |> Repo.all()
      assert length(results) == 1
      assert hd(results).id == sound.id
    end

    test "list_files/0 returns all sounds with tags and settings", %{sound: sound, tag: tag} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, tenant_id, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        [sound.id, tag.id, sound.tenant_id, now, now]
      )

      result = Sound.list_files() |> Enum.find(&(&1.id == sound.id))
      assert result.id == sound.id
      assert [%{name: "test_tag"}] = result.tags
    end

    test "get_sound!/1 loads all associations", %{sound: sound, tag: tag} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, tenant_id, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        [sound.id, tag.id, sound.tenant_id, now, now]
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

  describe "get_sound_id/1" do
    test "returns sound id when sound exists", %{sound: sound} do
      assert Sound.get_sound_id(sound.filename) == sound.id
    end

    test "returns nil when sound doesn't exist" do
      assert Sound.get_sound_id("nonexistent.mp3") == nil
    end
  end

  describe "get_recent_uploads/1" do
    test "returns recent uploads with default limit", %{user: user} do
      # Create multiple sounds
      _sounds =
        for _i <- 1..12 do
          {:ok, sound} = insert_sound(user)
          sound
        end

      results = Sound.get_recent_uploads()

      # Should return 10 most recent
      assert length(results) >= 10

      # Verify the structure of results
      {filename, username, timestamp} = hd(results)
      assert is_binary(filename)
      assert is_binary(username)
      assert %NaiveDateTime{} = timestamp

      # At least one should belong to our test user
      user_results = Enum.filter(results, fn {_, uname, _} -> uname == user.username end)
      assert length(user_results) > 0
    end

    test "returns recent uploads with custom limit", %{user: user} do
      # Create 5 sounds
      for _ <- 1..5, do: insert_sound(user)

      results = Sound.get_recent_uploads(limit: 3)
      assert length(results) == 3
    end

    test "returns empty list when no sounds exist" do
      # Delete all sounds
      Repo.delete_all(Sound)

      results = Sound.get_recent_uploads()
      assert results == []
    end

    test "scopes results by tenant_id", %{user: user} do
      slug = "recent-#{System.unique_integer([:positive])}"

      {:ok, other_tenant} =
        %Tenant{}
        |> Tenant.changeset(%{name: "Recent Tenant", slug: slug, plan: :pro})
        |> Repo.insert()

      other_user = insert_user_for_tenant(other_tenant)

      # Existing setup inserted sounds for default tenant; add a couple for the other tenant
      for _ <- 1..3, do: insert_sound(other_user)

      results = Sound.get_recent_uploads(tenant_id: other_tenant.id)

      assert Enum.all?(results, fn {_filename, username, _ts} ->
               username == other_user.username
             end)

      refute Enum.any?(results, fn {_filename, username, _ts} -> username == user.username end)
    end
  end

  describe "update_sound/2" do
    test "updates sound attributes", %{sound: sound, tag: tag} do
      # Preload tags to avoid association error
      sound = Repo.preload(sound, :tags)

      attrs = %{
        description: "Updated description",
        tags: [tag]
      }

      {:ok, updated_sound} = Sound.update_sound(sound, attrs)

      assert updated_sound.description == "Updated description"
      assert length(updated_sound.tags) == 1
      assert hd(updated_sound.tags).id == tag.id
    end

    test "validates on update", %{sound: sound} do
      attrs = %{source_type: "invalid"}

      {:error, changeset} = Sound.update_sound(sound, attrs)
      assert "must be either 'local' or 'url'" in errors_on(changeset).source_type
    end
  end

  describe "user join/leave sounds" do
    test "get_user_join_sound/1 returns join sound filename", %{user: user, sound: sound} do
      # Create join sound setting
      {:ok, _} =
        UserSoundSetting.changeset(
          %UserSoundSetting{},
          %{
            user_id: user.id,
            sound_id: sound.id,
            is_join_sound: true,
            is_leave_sound: false
          }
        )
        |> Repo.insert()

      assert Sound.get_user_join_sound(user.id) == sound.filename
    end

    test "get_user_join_sound/1 returns nil when no join sound", %{user: user} do
      assert Sound.get_user_join_sound(user.id) == nil
    end

    test "get_user_leave_sound/1 returns leave sound filename", %{user: user, sound: sound} do
      # Create leave sound setting
      {:ok, _} =
        UserSoundSetting.changeset(
          %UserSoundSetting{},
          %{
            user_id: user.id,
            sound_id: sound.id,
            is_join_sound: false,
            is_leave_sound: true
          }
        )
        |> Repo.insert()

      assert Sound.get_user_leave_sound(user.id) == sound.filename
    end

    test "get_user_leave_sound/1 returns nil when no leave sound", %{user: user} do
      assert Sound.get_user_leave_sound(user.id) == nil
    end
  end

  describe "get_user_sounds_by_discord_id/1" do
    test "returns user sounds when user has join/leave sounds", %{user: user, sound: sound} do
      # Create setting with both join and leave
      {:ok, _} =
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

      result = Sound.get_user_sounds_by_discord_id(user.discord_id)
      {user_id, filename, is_join, is_leave} = result

      assert user_id == user.id
      assert filename == sound.filename
      assert is_join == true
      assert is_leave == true
    end

    test "returns user with nil sound when no join/leave sounds", %{user: user} do
      result = Sound.get_user_sounds_by_discord_id(user.discord_id)
      {user_id, filename, is_join, is_leave} = result

      assert user_id == user.id
      assert filename == nil
      assert is_join == nil
      assert is_leave == nil
    end

    test "returns nil when user doesn't exist" do
      assert Sound.get_user_sounds_by_discord_id("nonexistent_discord_id") == nil
    end
  end

  describe "changeset with tags" do
    test "associates tags when provided in attrs", %{user: user, tag: tag} do
      attrs = %{
        filename: "tagged_sound.mp3",
        source_type: "local",
        user_id: user.id,
        tags: [tag]
      }

      changeset = Sound.changeset(%Sound{}, attrs)
      assert changeset.valid?

      {:ok, sound} = Repo.insert(changeset)
      sound = Repo.preload(sound, :tags)

      assert length(sound.tags) == 1
      assert hd(sound.tags).id == tag.id
    end

    test "handles empty tags list", %{user: user} do
      attrs = %{
        filename: "no_tags_sound.mp3",
        source_type: "local",
        user_id: user.id,
        tags: []
      }

      changeset = Sound.changeset(%Sound{}, attrs)
      assert changeset.valid?

      {:ok, sound} = Repo.insert(changeset)
      sound = Repo.preload(sound, :tags)

      assert sound.tags == []
    end
  end

  # Helper functions
  defp insert_user do
    tenant = Tenants.ensure_default_tenant!()
    insert_user_for_tenant(tenant)
  end

  defp insert_user_for_tenant(tenant) do
    {:ok, user} =
      %Soundboard.Accounts.User{}
      |> User.changeset(%{
        username: "test_user_#{System.unique_integer()}",
        discord_id: "123456_#{System.unique_integer()}",
        avatar: "test.jpg",
        tenant_id: tenant.id
      })
      |> Repo.insert()

    user
  end

  defp insert_sound(user) do
    %Sound{}
    |> Sound.changeset(%{
      filename: "test_sound_#{System.unique_integer()}.mp3",
      source_type: "local",
      user_id: user.id,
      tenant_id: user.tenant_id
    })
    |> Repo.insert()
  end
end
