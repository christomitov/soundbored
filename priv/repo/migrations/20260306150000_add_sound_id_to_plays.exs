defmodule Soundboard.Repo.Migrations.AddSoundIdToPlays do
  use Ecto.Migration

  def up do
    alter table(:plays) do
      add :sound_id, references(:sounds, on_delete: :nilify_all)
    end

    execute("""
    UPDATE plays
    SET sound_id = (
      SELECT sounds.id
      FROM sounds
      WHERE sounds.filename = plays.sound_name
    )
    WHERE sound_id IS NULL
    """)

    create index(:plays, [:sound_id])
  end

  def down do
    drop index(:plays, [:sound_id])

    alter table(:plays) do
      remove :sound_id
    end
  end
end
