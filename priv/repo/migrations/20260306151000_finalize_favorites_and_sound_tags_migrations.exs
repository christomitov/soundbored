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

    alter table(:sounds) do
      remove :tags
    end
  end

  def down do
    alter table(:sounds) do
      add :tags, {:array, :string}, default: []
    end

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
