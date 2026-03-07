for migration_file <- [
      "20250101213201_create_sounds.exs",
      "20250101213717_create_tags.exs",
      "20250101231744_create_users.exs",
      "20250102212120_create_plays.exs",
      "20250102212121_create_favorites.exs",
      "20250102212122_add_user_id_to_sounds.exs",
      "20250102212123_change_favorites_filename_to_sound_id.exs",
      "20260306150000_add_sound_id_to_plays.exs",
      "20260306151000_finalize_favorites_and_sound_tags_migrations.exs"
    ] do
  Code.require_file(Path.expand("../../../priv/repo/migrations/#{migration_file}", __DIR__))
end

defmodule Soundboard.Migrations.DataMigrationsTest do
  use ExUnit.Case, async: false

  alias Soundboard.Repo.Migrations.{
    AddSoundIdToPlays,
    AddUserIdToSounds,
    ChangeFavoritesFilenameToSoundId,
    CreateFavorites,
    CreatePlays,
    CreateSounds,
    CreateTags,
    CreateUsers,
    FinalizeFavoritesAndSoundTagsMigrations
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
