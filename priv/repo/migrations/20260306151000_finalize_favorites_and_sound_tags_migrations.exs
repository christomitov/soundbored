defmodule Soundboard.Repo.Migrations.FinalizeFavoritesAndSoundTagsMigrations do
  use Ecto.Migration

  def up do
    create table(:favorites_new) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :sound_id, references(:sounds, on_delete: :delete_all), null: false
      timestamps()
    end

    execute("""
    INSERT INTO favorites_new (user_id, sound_id, inserted_at, updated_at)
    SELECT f.user_id, f.sound_id, f.inserted_at, f.updated_at
    FROM favorites f
    JOIN sounds s ON s.id = f.sound_id
    """)

    drop table(:favorites)
    execute("ALTER TABLE favorites_new RENAME TO favorites")

    create unique_index(:favorites, [:user_id, :sound_id])
    create index(:favorites, [:sound_id])

    execute("""
    INSERT INTO tags (name, inserted_at, updated_at)
    SELECT DISTINCT lower(trim(j.value)), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    FROM sounds s
    JOIN json_each(s.tags) AS j
    WHERE json_valid(s.tags)
      AND trim(j.value) != ''
      AND NOT EXISTS (
        SELECT 1 FROM tags existing WHERE existing.name = lower(trim(j.value))
      )
    """)

    execute("""
    INSERT INTO sound_tags (sound_id, tag_id, inserted_at, updated_at)
    SELECT s.id, t.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    FROM sounds s
    JOIN json_each(s.tags) AS j
    JOIN tags t ON t.name = lower(trim(j.value))
    WHERE json_valid(s.tags)
      AND trim(j.value) != ''
      AND NOT EXISTS (
        SELECT 1
        FROM sound_tags st
        WHERE st.sound_id = s.id AND st.tag_id = t.id
      )
    """)

    alter table(:sounds) do
      remove :tags
    end
  end

  def down do
    alter table(:sounds) do
      add :tags, {:array, :string}, default: []
    end

    execute("""
    UPDATE sounds
    SET tags = COALESCE((
      SELECT json_group_array(name)
      FROM (
        SELECT t.name AS name
        FROM sound_tags st
        JOIN tags t ON t.id = st.tag_id
        WHERE st.sound_id = sounds.id
        ORDER BY t.name
      )
    ), '[]')
    """)

    create table(:favorites_new) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :sound_id, :integer, null: false
      timestamps()
    end

    execute("""
    INSERT INTO favorites_new (user_id, sound_id, inserted_at, updated_at)
    SELECT user_id, sound_id, inserted_at, updated_at
    FROM favorites
    """)

    drop table(:favorites)
    execute("ALTER TABLE favorites_new RENAME TO favorites")

    create unique_index(:favorites, [:user_id, :sound_id])
  end
end
