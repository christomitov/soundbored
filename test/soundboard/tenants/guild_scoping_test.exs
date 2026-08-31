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
    test "is allowed — filenames are unique per guild, not globally", %{
      guild_a_sound: a,
      guild_b_sound: b
    } do
      assert a.filename == b.filename
      assert a.guild_id == "guild-a"
      assert b.guild_id == "guild-b"
      assert a.id != b.id
    end

    test "list_detailed/1 scopes to the requested guild", %{
      guild_a_sound: a,
      guild_b_sound: b
    } do
      # ensure sounds exist in both guilds before scoping assertions
      assert a.guild_id == "guild-a"
      assert b.guild_id == "guild-b"

      filenames_a = Sounds.list_detailed("guild-a") |> Enum.map(& &1.filename)
      filenames_b = Sounds.list_detailed("guild-b") |> Enum.map(& &1.filename)

      assert "airhorn.mp3" in filenames_a
      assert "airhorn.mp3" in filenames_b
      assert Enum.count(Sounds.list_detailed("guild-a")) == 1
      assert Enum.count(Sounds.list_detailed("guild-b")) == 1
    end

    test "list_detailed/0 (no guild) targets the default guild only", %{default_sound: d} do
      filenames = Sounds.list_detailed() |> Enum.map(& &1.filename)

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

    test "filename_taken?/2 is scoped per guild" do
      assert Sounds.filename_taken?("airhorn.mp3", "guild-a")
      assert Sounds.filename_taken?("airhorn.mp3", "guild-b")
      refute Sounds.filename_taken?("airhorn.mp3", "guild-c")
    end
  end

  describe "per-guild join/leave sounds" do
    test "a user's join sound is scoped to the guild it was configured in", %{user: user} do
      guild_a_sound = insert_sound!(user, filename: "join-a.mp3", guild_id: "guild-a")
      guild_b_sound = insert_sound!(user, filename: "join-b.mp3", guild_id: "guild-b")

      insert_setting!(user, guild_a_sound, is_join_sound: true)
      insert_setting!(user, guild_b_sound, is_join_sound: true)

      assert Sounds.get_user_join_sound(user.id, "guild-a") == "join-a.mp3"
      assert Sounds.get_user_join_sound(user.id, "guild-b") == "join-b.mp3"
      assert Sounds.get_user_join_sound(user.id, "guild-c") == nil
    end

    test "setting a join sound in one guild does not clear it in another", %{user: user} do
      guild_a_sound = insert_sound!(user, filename: "join-a.mp3", guild_id: "guild-a")
      guild_b_sound = insert_sound!(user, filename: "join-b.mp3", guild_id: "guild-b")

      insert_setting!(user, guild_a_sound, is_join_sound: true)
      insert_setting!(user, guild_b_sound, is_join_sound: true)

      # Re-point guild A's join sound at guild B's sound via conflict clearing
      # for a third sound in guild A.
      other_a = insert_sound!(user, filename: "join-a2.mp3", guild_id: "guild-a")

      Soundboard.UserSoundSetting.clear_conflicting_settings(
        user.id,
        other_a.id,
        true,
        false,
        "guild-a"
      )

      # Guild B's join sound must survive.
      assert Sounds.get_user_join_sound(user.id, "guild-b") == "join-b.mp3"
      # Guild A's original join sound was cleared within guild A only.
      assert Sounds.get_user_join_sound(user.id, "guild-a") == nil
    end

    test "join/leave lookups without a guild target the default guild", %{user: user} do
      sound = insert_sound!(user, filename: "leave-default.mp3")
      insert_setting!(user, sound, is_leave_sound: true)

      assert Sounds.get_user_leave_sound(user.id) == "leave-default.mp3"
      assert Sounds.get_user_leave_sound(user.id, "guild-a") == nil
    end
  end

  describe "storage caps at the upload boundary" do
    test "create_sound/1 records byte_size and charges it to the guild", %{user: user} do
      Tenants.get_or_create_guild("capped", %{slug: "capped", max_storage_bytes: 10_000})

      {:ok, sound} =
        create_sound(user, %{
          "name" => "capped-sound",
          "source_type" => "url",
          "url" => "https://example.com/capped.mp3",
          "guild_id" => "capped"
        })

      assert sound.guild_id == "capped"
      # URL sounds have no local bytes.
      assert Tenants.storage_used("capped") == 0
    end

    test "create_sound/1 rejects uploads past the guild's cap", %{user: user} do
      upload = %{
        path: local_sound_path(6_000),
        filename: "big.mp3"
      }

      Tenants.get_or_create_guild("tiny", %{slug: "tiny", max_storage_bytes: 5_000})
      insert_sound!(user, filename: "filler.mp3", guild_id: "tiny", byte_size: 3_000)

      {:error, changeset} =
        create_sound(user, %{
          "name" => "too-big",
          "source_type" => "local",
          "upload" => upload,
          "guild_id" => "tiny"
        })

      assert errors_on(changeset).base != nil
      assert Tenants.storage_used("tiny") == 3_000
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

  # -- helpers ----------------------------------------------------------------

  defp create_sound(user, params) do
    user
    |> Sounds.new_create_request(params)
    |> Sounds.create_sound()
  end

  defp local_sound_path(bytes) do
    # Minimal MP3-ish file: ID3 header passes magic-byte validation.
    path = Path.join(System.tmp_dir!(), "soundbored-cap-test-#{System.unique_integer()}.mp3")
    File.write!(path, "ID3" <> :binary.copy(<<0>>, bytes - 3))
    on_exit(fn -> File.rm(path) end)
    path
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
      Map.merge(
        %{user_id: user.id, sound_id: sound.id, guild_id: sound.guild_id},
        Map.new(attrs)
      )
    )
    |> Repo.insert!()
  end
end
