defmodule Soundboard.Repo.Migrations.RemoveJoinLeaveFlagsFromSounds do
  use Ecto.Migration

  def change do
    # First create a new sounds table without the join/leave columns
    create table(:sounds_new) do
      add :filename, :string, null: false
      add :description, :string
      add :user_id, references(:users, on_delete: :nilify_all)
      add :source_type, :string, default: "local", null: false
      add :url, :string

      timestamps()
    end

    # Copy data
    execute """
    INSERT INTO sounds_new (id, filename, description, user_id, source_type, url, inserted_at, updated_at)
    SELECT id, filename, description, user_id, source_type, url, inserted_at, updated_at
    FROM sounds;
    """

    drop table(:sounds)

    execute """
    ALTER TABLE sounds_new RENAME TO sounds;
    """
  end
end
