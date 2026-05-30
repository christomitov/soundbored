defmodule Soundboard.Repo.Migrations.FixOrphanedStorageKeys do
  use Ecto.Migration
  require Logger

  # Repairs sounds whose storage_key file doesn't exist on disk but whose
  # display filename file does — i.e. the rename in AddStorageKeyToSounds
  # was silently skipped because the uploads path differed at migration time.
  def up do
    {:ok, rows} =
      Soundboard.Repo.query(
        "SELECT id, filename, storage_key FROM sounds WHERE source_type = 'local'"
      )

    uploads_dir = Soundboard.UploadsPath.dir()

    Enum.each(rows.rows, fn [id, filename, storage_key] ->
      uuid_path = Path.join(uploads_dir, storage_key)
      old_path = Path.join(uploads_dir, filename)

      cond do
        File.exists?(uuid_path) ->
          :ok

        File.exists?(old_path) ->
          Logger.info(
            "FixOrphanedStorageKeys: renaming #{old_path} → #{uuid_path} for sound id=#{id}"
          )

          File.rename!(old_path, uuid_path)

        true ->
          Logger.warning(
            "FixOrphanedStorageKeys: no file found for sound id=#{id} " <>
              "(checked #{uuid_path} and #{old_path})"
          )
      end
    end)
  end

  def down, do: :ok
end
