for migration_file <- [
      "20250101213201_create_sounds.exs",
      "20250101213717_create_tags.exs",
      "20250101231744_create_users.exs",
      "20250102212120_create_plays.exs",
      "20250102212121_create_favorites.exs",
      "20250102212122_add_user_id_to_sounds.exs",
      "20250102212125_add_join_leave_flags_to_sounds.exs",
      "20250102212126_add_url_to_sounds.exs",
      "20250218214831_create_user_sound_settings.exs",
      "20250218214832_remove_join_leave_flags_from_sounds.exs",
      "20250102212123_change_favorites_filename_to_sound_id.exs",
      "20260306150000_add_sound_id_to_plays.exs",
      "20260306151000_finalize_favorites_and_sound_tags_migrations.exs",
      "20260307211000_rename_sound_name_to_played_filename_in_plays.exs",
      "20260510000001_remove_token_plain_from_api_tokens.exs",
      "20260510000002_add_storage_key_to_sounds.exs",
      "20260831120000_create_guilds.exs",
      "20260831120100_add_guild_id_to_sounds.exs"
    ] do
  Code.require_file(Application.app_dir(:soundboard, "priv/repo/migrations/#{migration_file}"))
end

defmodule Soundboard.Migrations.DataMigrationsTest do
  use ExUnit.Case, async: false

  alias Soundboard.Repo.Migrations.{
    AddGuildIdToSounds,
    AddJoinLeaveFlagsToSounds,
    AddSoundIdToPlays,
    AddUrlToSounds,
    AddUserIdToSounds,
    ChangeFavoritesFilenameToSoundId,
    CreateFavorites,
    CreateGuilds,
    CreatePlays,
    CreateSounds,
    CreateTags,
    CreateUsers,
    CreateUserSoundSettings,
    FinalizeFavoritesAndSoundTagsMigrations,
    RemoveJoinLeaveFlagsFromSounds,
    RenameSoundNameToPlayedFilenameInPlays
  }

  defmodule MigrationRepo do
    use Ecto.Repo,
      otp_app: :soundboard,
      adapter: Ecto.Adapters.SQLite3
  end

  setup do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "soundboard-migration-#{System.unique_integer([:positive])}.db"
      )

    {:ok, pid} = MigrationRepo.start_link(database: db_path, pool_size: 1, name: nil)
    previous_repo = MigrationRepo.put_dynamic_repo(pid)

    on_exit(fn ->
      MigrationRepo.put_dynamic_repo(previous_repo)
      Process.exit(pid, :normal)
      File.rm(db_path)
    end)

    %{repo: MigrationRepo}
  end

  test "add_sound_id_to_plays backfills matching sound ids and rolls back cleanly", %{repo: repo} do
    migrate_up(repo, [
      {20_250_101_213_201, CreateSounds},
      {20_250_101_231_744, CreateUsers},
      {20_250_102_212_120, CreatePlays},
      {20_250_102_212_122, AddUserIdToSounds}
    ])

    repo.query!("""
    INSERT INTO users (id, discord_id, username, avatar, inserted_at, updated_at)
    VALUES (1, 'discord-1', 'tester', 'avatar.png', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    repo.query!("""
    INSERT INTO sounds (id, filename, tags, description, user_id, inserted_at, updated_at)
    VALUES (1, 'beep.mp3', '[]', NULL, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    repo.query!("""
    INSERT INTO plays (id, sound_name, user_id, inserted_at, updated_at)
    VALUES (1, 'beep.mp3', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    :ok = Ecto.Migrator.up(repo, 20_260_306_150_000, AddSoundIdToPlays, log: false)

    assert column_names(repo, "plays") |> Enum.member?("sound_id")
    assert [[1]] = repo.query!("SELECT sound_id FROM plays WHERE id = 1").rows

    :ok = Ecto.Migrator.down(repo, 20_260_306_150_000, AddSoundIdToPlays, log: false)

    refute column_names(repo, "plays") |> Enum.member?("sound_id")
  end

  test "rename_sound_name_to_played_filename_in_plays renames the column and rolls back cleanly",
       %{repo: repo} do
    migrate_up(repo, [
      {20_250_101_213_201, CreateSounds},
      {20_250_101_231_744, CreateUsers},
      {20_250_102_212_120, CreatePlays},
      {20_250_102_212_122, AddUserIdToSounds},
      {20_260_306_150_000, AddSoundIdToPlays}
    ])

    repo.query!("""
    INSERT INTO users (id, discord_id, username, avatar, inserted_at, updated_at)
    VALUES (1, 'discord-1', 'tester', 'avatar.png', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    repo.query!("""
    INSERT INTO sounds (id, filename, tags, description, user_id, inserted_at, updated_at)
    VALUES (1, 'beep.mp3', '[]', NULL, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    repo.query!("""
    INSERT INTO plays (id, sound_name, user_id, inserted_at, updated_at)
    VALUES (1, 'beep.mp3', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    :ok =
      Ecto.Migrator.up(
        repo,
        20_260_307_211_000,
        RenameSoundNameToPlayedFilenameInPlays,
        log: false
      )

    assert column_names(repo, "plays") |> Enum.member?("played_filename")
    refute column_names(repo, "plays") |> Enum.member?("sound_name")

    assert [["beep.mp3", 1]] =
             repo.query!("SELECT played_filename, sound_id FROM plays WHERE id = 1").rows

    :ok =
      Ecto.Migrator.down(
        repo,
        20_260_307_211_000,
        RenameSoundNameToPlayedFilenameInPlays,
        log: false
      )

    assert column_names(repo, "plays") |> Enum.member?("sound_name")
    refute column_names(repo, "plays") |> Enum.member?("played_filename")
  end

  test "finalize favorites and sound tags backfills legacy tags and restores them on rollback", %{
    repo: repo
  } do
    migrate_up(repo, [
      {20_250_101_213_201, CreateSounds},
      {20_250_101_213_717, CreateTags},
      {20_250_101_231_744, CreateUsers},
      {20_250_102_212_121, CreateFavorites},
      {20_250_102_212_122, AddUserIdToSounds},
      {20_250_102_212_123, ChangeFavoritesFilenameToSoundId}
    ])

    repo.query!("""
    INSERT INTO users (id, discord_id, username, avatar, inserted_at, updated_at)
    VALUES (1, 'discord-1', 'tester', 'avatar.png', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    repo.query!("""
    INSERT INTO sounds (id, filename, tags, description, user_id, inserted_at, updated_at)
    VALUES (1, 'beep.mp3', '[" meme ","MEME","alert",""]', NULL, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    repo.query!("""
    INSERT INTO tags (id, name, inserted_at, updated_at)
    VALUES (1, 'meme', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    repo.query!("""
    INSERT INTO sound_tags (sound_id, tag_id, inserted_at, updated_at)
    VALUES (1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    repo.query!("""
    INSERT INTO favorites (user_id, sound_id, inserted_at, updated_at)
    VALUES (1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
           (1, 999, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    :ok =
      Ecto.Migrator.up(
        repo,
        20_260_306_151_000,
        FinalizeFavoritesAndSoundTagsMigrations,
        log: false
      )

    refute column_names(repo, "sounds") |> Enum.member?("tags")

    assert [["alert"], ["meme"]] =
             repo.query!("SELECT name FROM tags ORDER BY name").rows

    assert [[1, 1]] =
             repo.query!("SELECT user_id, sound_id FROM favorites ORDER BY sound_id").rows

    assert [[1, 1], [1, 2]] =
             repo.query!("SELECT sound_id, tag_id FROM sound_tags ORDER BY tag_id").rows

    :ok =
      Ecto.Migrator.down(
        repo,
        20_260_306_151_000,
        FinalizeFavoritesAndSoundTagsMigrations,
        log: false
      )

    assert column_names(repo, "sounds") |> Enum.member?("tags")
    assert [["[\"alert\",\"meme\"]"]] = repo.query!("SELECT tags FROM sounds WHERE id = 1").rows
  end

  test "guild scoping migration backfills existing data into the default guild and rolls back",
       %{repo: repo} do
    migrate_up(repo, [
      {20_250_101_213_201, CreateSounds},
      {20_250_101_231_744, CreateUsers},
      {20_250_102_212_122, AddUserIdToSounds},
      {20_250_102_212_125, AddJoinLeaveFlagsToSounds},
      {20_250_102_212_126, AddUrlToSounds},
      {20_250_218_214_831, CreateUserSoundSettings},
      {20_250_218_214_832, RemoveJoinLeaveFlagsFromSounds}
    ])

    # Pre-tenant production schema: AddStorageKeyToSounds touches the global
    # Repo (file renames), so mirror its schema change directly.
    repo.query!("ALTER TABLE sounds ADD COLUMN storage_key TEXT NOT NULL DEFAULT ''")
    repo.query!("ALTER TABLE sounds ADD COLUMN volume REAL DEFAULT 1.0")
    repo.query!("CREATE UNIQUE INDEX sounds_storage_key_index ON sounds (storage_key)")

    repo.query!("""
    INSERT INTO users (id, discord_id, username, avatar, inserted_at, updated_at)
    VALUES (1, 'discord-1', 'tester', 'avatar.png', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    repo.query!("""
    INSERT INTO sounds (id, filename, user_id, storage_key, volume, inserted_at, updated_at)
    VALUES (1, 'beep.mp3', 1, 'key-1.mp3', 1.0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    repo.query!("""
    INSERT INTO sounds (id, filename, user_id, storage_key, volume, inserted_at, updated_at)
    VALUES (2, 'boop.mp3', 1, 'key-2.mp3', 1.0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    repo.query!("""
    INSERT INTO user_sound_settings (id, user_id, sound_id, is_join_sound, is_leave_sound, inserted_at, updated_at)
    VALUES (1, 1, 1, 1, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    # -- production upgrade: run the tenant migrations in place ---------------
    :ok = Ecto.Migrator.up(repo, 20_260_831_120_000, CreateGuilds, log: false)
    :ok = Ecto.Migrator.up(repo, 20_260_831_120_100, AddGuildIdToSounds, log: false)

    # No data was lost.
    assert [[2]] = repo.query!("SELECT count(*) FROM sounds").rows
    assert [[1]] = repo.query!("SELECT count(*) FROM user_sound_settings").rows

    # Existing sounds are backfilled into the default guild...
    default_guild = Soundboard.Tenants.default_guild_id()
    rows = repo.query!("SELECT DISTINCT guild_id FROM sounds").rows
    assert Enum.all?(rows, fn [guild_id] -> guild_id == default_guild end)

    # ...with unknown sizes (so caps never block retroactively).
    sizes = repo.query!("SELECT DISTINCT byte_size FROM sounds").rows
    assert Enum.all?(sizes, fn [size] -> size == 0 end)

    # Sound settings inherit their sound's guild.
    setting_guilds = repo.query!("SELECT DISTINCT guild_id FROM user_sound_settings").rows

    assert Enum.all?(setting_guilds, fn [guild_id] -> guild_id == default_guild end)

    # Same filename is now allowed per guild...
    repo.query!("""
    INSERT INTO sounds (id, filename, user_id, storage_key, guild_id, volume, inserted_at, updated_at)
    VALUES (3, 'beep.mp3', 1, 'key-3.mp3', 'other-guild', 1.0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    # ...but still unique within one guild.
    assert_raise(Exqlite.Error, ~r/UNIQUE constraint failed/, fn ->
      repo.query!("""
      INSERT INTO sounds (id, filename, user_id, storage_key, guild_id, volume, inserted_at, updated_at)
      VALUES (4, 'beep.mp3', 1, 'key-4.mp3', '#{default_guild}', 1.0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      """)
    end)

    # A tenant row created after the migration may have a NULL cap; the
    # runtime fallback (Tenants.storage_cap/1, unit-tested) applies the
    # platform default in that case.
    repo.query!("""
    INSERT INTO guilds (id, discord_guild_id, slug, name, max_storage_bytes, inserted_at, updated_at)
    VALUES (1, '555', 'acme', 'Acme', NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    """)

    assert [[nil]] = repo.query!("SELECT max_storage_bytes FROM guilds WHERE id = 1").rows

    # -- rollback restores the pre-tenant schema without data loss ------------
    :ok = Ecto.Migrator.down(repo, 20_260_831_120_100, AddGuildIdToSounds, log: false)
    :ok = Ecto.Migrator.down(repo, 20_260_831_120_000, CreateGuilds, log: false)

    refute column_names(repo, "sounds") |> Enum.member?("guild_id")
    refute column_names(repo, "sounds") |> Enum.member?("byte_size")
    refute column_names(repo, "user_sound_settings") |> Enum.member?("guild_id")
    assert [[3]] = repo.query!("SELECT count(*) FROM sounds").rows
  end

  defp migrate_up(repo, migrations) do
    Enum.each(migrations, fn {version, migration} ->
      :ok = Ecto.Migrator.up(repo, version, migration, log: false)
    end)
  end

  defp column_names(repo, table_name) do
    repo.query!("PRAGMA table_info(#{table_name})")
    |> Map.fetch!(:rows)
    |> Enum.map(fn [_cid, name | _rest] -> name end)
  end
end
