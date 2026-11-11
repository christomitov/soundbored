defmodule Soundboard.Tenants.GuildScopingTest do
  @moduledoc """
  Behavioral tests for guild-scoped sound data: two tenants sharing a
  deployment must not see or affect each other's sounds.

  Backward compatibility is covered here too: every operation called without
  an explicit guild must behave exactly as the pre-tenant single-guild app did.
  """

  use Soundboard.DataCase, async: false

  alias Soundboard.{Accounts.User, Repo, Sounds, Tenants}

  setup do
    user = Repo.insert!(%User{discord_id: "scoping-1", username: "scoping-tester"})

    guild_a_sound = insert_sound!(user, filename: "airhorn.mp3", guild_id: "guild-a")
    guild_b_sound = insert_sound!(user, filename: "airhorn.mp3", guild_id: "guild-b")
    default_sound = insert_sound!(user, filename: "default-only.mp3")

    %{
      user: user,
      guild_a_sound: guild_a_sound,
      guild_b_sound: guild_b_sound,
      default_sound: default_sound
    }
  end

  describe "same filename in two guilds" do
    test "list_detailed/1 scopes to the requested guild", %{
      guild_a_sound: a,
      guild_b_sound: b
    } do
      assert Enum.map(Sounds.list_detailed("guild-a"), & &1.id) == [a.id]
      assert Enum.map(Sounds.list_detailed("guild-b"), & &1.id) == [b.id]
    end

    test "list_detailed/0 (no guild) targets the default guild only", %{default_sound: d} do
      filenames = Enum.map(Sounds.list_detailed(), & &1.filename)

      assert filenames == [d.filename]
    end

    test "fetch_sound_id/2 resolves within the requested guild", %{
      guild_a_sound: a,
      guild_b_sound: b
    } do
      assert {:ok, a_id} = Sounds.fetch_sound_id("airhorn.mp3", "guild-a")
      assert {:ok, b_id} = Sounds.fetch_sound_id("airhorn.mp3", "guild-b")
      assert a_id == a.id
      assert b_id == b.id
      assert :error == Sounds.fetch_sound_id("airhorn.mp3", "guild-c")
    end

    test "fetch_sound_id/1 (no guild) resolves in the default guild", %{default_sound: d} do
      assert {:ok, d_id} = Sounds.fetch_sound_id("default-only.mp3")
      assert d_id == d.id
      assert :error == Sounds.fetch_sound_id("default-only.mp3", "guild-a")
    end
  end

  describe "per-guild join/leave sounds" do
    test "a user's join sound is found only in the guild it was set in", %{user: user} do
      sound = insert_sound!(user, filename: "join-a.mp3", guild_id: "guild-a")
      insert_setting!(user, sound, is_join_sound: true)

      assert Sounds.get_user_join_sound_by_discord_id(user.discord_id, "guild-a") == "join-a.mp3"
      assert Sounds.get_user_join_sound_by_discord_id(user.discord_id, "guild-b") == nil
    end

    test "setting a join sound in one guild does not clear it in another", %{user: user} do
      guild_a_sound = insert_sound!(user, filename: "join-a.mp3", guild_id: "guild-a")
      guild_b_sound = insert_sound!(user, filename: "join-b.mp3", guild_id: "guild-b")

      insert_setting!(user, guild_a_sound, is_join_sound: true)
      insert_setting!(user, guild_b_sound, is_join_sound: true)

      other_a = insert_sound!(user, filename: "join-a2.mp3", guild_id: "guild-a")

      Soundboard.UserSoundSetting.clear_conflicting_settings(
        user.id,
        other_a.id,
        true,
        false,
        "guild-a"
      )

      assert Sounds.get_user_join_sound_by_discord_id(user.discord_id, "guild-b") == "join-b.mp3"
      assert Sounds.get_user_join_sound_by_discord_id(user.discord_id, "guild-a") == nil
    end

    test "join/leave lookups without a guild target the default guild", %{user: user} do
      sound = insert_sound!(user, filename: "leave-default.mp3")
      insert_setting!(user, sound, is_leave_sound: true)

      assert Sounds.get_user_leave_sound_by_discord_id(user.discord_id) == "leave-default.mp3"
      assert Sounds.get_user_leave_sound_by_discord_id(user.discord_id, "guild-a") == nil
    end
  end

  describe "storage caps at the upload boundary" do
    test "create_sound/1 records a local file's size and charges it to the guild", %{
      user: user
    } do
      Tenants.get_or_create_guild("capped", %{slug: "capped", max_storage_bytes: 10_000_000})
      path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-capped.mp3")
      File.cp!(Soundboard.TestHelpers.audio_fixture_path(), path)
      on_exit(fn -> File.rm(path) end)

      {:ok, sound} =
        user
        |> Sounds.new_create_request(%{"name" => "capped-sound", "guild_id" => "capped"})
        |> Sounds.put_request_upload(%{path: path, filename: "capped.mp3"})
        |> Sounds.create_sound()

      on_exit(fn -> File.rm(Soundboard.UploadsPath.file_path(sound.storage_key)) end)

      assert sound.byte_size == File.stat!(path).size
      assert sound.byte_size > 0
      assert Tenants.storage_used("capped") == sound.byte_size
    end

    test "create_sound/1 without a guild lands in the default guild (back-compat)", %{user: user} do
      {:ok, sound} =
        create_sound(user, %{
          "name" => "no-tenant",
          "source_type" => "url",
          "url" => "https://example.com/tenantless.mp3"
        })

      assert sound.guild_id == Tenants.default_guild_id()
      assert {:ok, sound_id} = Sounds.fetch_sound_id("no-tenant.mp3")
      assert sound_id == sound.id
    end

    test "create_sound/1 allows the same name in two guilds", %{user: user} do
      for guild <- ["x1", "x2"] do
        Tenants.get_or_create_guild(guild, %{slug: "g-#{guild}"})

        {:ok, sound} =
          create_sound(user, %{
            "name" => "dupe",
            "source_type" => "url",
            "url" => "https://example.com/dupe.mp3",
            "guild_id" => guild
          })

        assert sound.guild_id == guild
      end
    end
  end

  defp create_sound(user, params) do
    user
    |> Sounds.new_create_request(params)
    |> Sounds.create_sound()
  end

  defp insert_sound!(user, attrs) do
    defaults = [
      filename: Keyword.fetch!(attrs, :filename),
      storage_key: Ecto.UUID.generate() <> ".mp3",
      source_type: "url",
      url: "https://example.com/#{Keyword.fetch!(attrs, :filename)}",
      user_id: user.id
    ]

    %Soundboard.Sound{}
    |> Soundboard.Sound.changeset(Map.new(Enum.concat(defaults, attrs)))
    |> Repo.insert!()
  end

  defp insert_setting!(user, sound, attrs) do
    %Soundboard.UserSoundSetting{}
    |> Soundboard.UserSoundSetting.changeset(
      Map.merge(%{user_id: user.id, sound_id: sound.id, guild_id: sound.guild_id}, Map.new(attrs))
    )
    |> Repo.insert!()
  end
end
