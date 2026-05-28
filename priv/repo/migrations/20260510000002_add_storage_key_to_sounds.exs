defmodule Soundboard.Repo.Migrations.AddStorageKeyToSounds do
  use Ecto.Migration

  def up do
    alter table(:sounds) do
      add :storage_key, :string, null: false, default: ""
    end

    flush()

    # Populate storage_key for existing sounds by generating a UUID per row
    # and renaming the file on disk to match.
    {:ok, rows} = Soundboard.Repo.query("SELECT id, filename FROM sounds")
    uploads_dir = Soundboard.UploadsPath.dir()

    Enum.each(rows.rows, fn [id, filename] ->
      ext = Path.extname(filename)
      storage_key = Ecto.UUID.generate() <> ext
      old_path = Path.join(uploads_dir, filename)
      new_path = Path.join(uploads_dir, storage_key)

      if File.exists?(old_path), do: File.rename!(old_path, new_path)

      Soundboard.Repo.query!(
        "UPDATE sounds SET storage_key = ? WHERE id = ?",
        [storage_key, id]
      )
    end)

    create unique_index(:sounds, [:storage_key])
  end

  def down do
    # Reverse: rename UUID-named files back to their display filenames
    {:ok, rows} = Soundboard.Repo.query("SELECT filename, storage_key FROM sounds")
    uploads_dir = Soundboard.UploadsPath.dir()

    Enum.each(rows.rows, fn [filename, storage_key] ->
      old_path = Path.join(uploads_dir, storage_key)
      new_path = Path.join(uploads_dir, filename)
      if File.exists?(old_path), do: File.rename!(old_path, new_path)
    end)

    drop_if_exists index(:sounds, [:storage_key])

    alter table(:sounds) do
      remove :storage_key
    end
  end
end
