defmodule Soundboard.Repo.Migrations.RenameSoundNameToPlayedFilenameInPlays do
  use Ecto.Migration

  def up do
    drop_if_exists index(:plays, [:sound_name])

    rename table(:plays), :sound_name, to: :played_filename

    execute("""
    UPDATE plays
    SET sound_id = (
      SELECT sounds.id
      FROM sounds
      WHERE sounds.filename = plays.played_filename
    )
    WHERE sound_id IS NULL
    """)

    create index(:plays, [:played_filename])
  end

  def down do
    drop_if_exists index(:plays, [:played_filename])

    rename table(:plays), :played_filename, to: :sound_name

    create index(:plays, [:sound_name])
  end
end
