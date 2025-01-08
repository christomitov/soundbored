defmodule Soundboard.Repo.Migrations.ChangeFavoritesFilenameToSoundId do
  use Ecto.Migration

  def up do
    # First add the new column while keeping the old one
    alter table(:favorites) do
      add :sound_id, :integer
    end

    # Copy data from filename to sound_id by joining with sounds table
    execute """
    UPDATE favorites SET sound_id = (
      SELECT id FROM sounds WHERE sounds.filename = favorites.filename
    )
    """

    # Create a new table with the desired schema
    create table(:favorites_new) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :sound_id, :integer, null: false
      timestamps()
    end

    # Copy data to the new table
    execute """
    INSERT INTO favorites_new (user_id, sound_id, inserted_at, updated_at)
    SELECT user_id, sound_id, inserted_at, updated_at FROM favorites
    WHERE sound_id IS NOT NULL
    """

    # Drop the old table and rename the new one
    drop table(:favorites)
    execute "ALTER TABLE favorites_new RENAME TO favorites"

    # Create the new index
    create unique_index(:favorites, [:user_id, :sound_id])
  end

  def down do
    # Create a new table with the old schema
    create table(:favorites_new) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :filename, :string, null: false
      timestamps()
    end

    # Copy data back by joining with sounds table
    execute """
    INSERT INTO favorites_new (user_id, filename, inserted_at, updated_at)
    SELECT f.user_id, s.filename, f.inserted_at, f.updated_at
    FROM favorites f
    JOIN sounds s ON s.id = f.sound_id
    """

    # Drop the old table and rename the new one
    drop table(:favorites)
    execute "ALTER TABLE favorites_new RENAME TO favorites"

    # Recreate the old index
    create unique_index(:favorites, [:user_id, :filename],
             name: :favorites_user_id_filename_index
           )
  end
end
