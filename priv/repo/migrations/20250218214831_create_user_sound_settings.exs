defmodule Soundboard.Repo.Migrations.CreateUserSoundSettings do
  use Ecto.Migration

  def change do
    create table(:user_sound_settings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :sound_id, references(:sounds, on_delete: :delete_all), null: false
      add :is_join_sound, :boolean, default: false
      add :is_leave_sound, :boolean, default: false

      timestamps()
    end

    create index(:user_sound_settings, [:user_id])
    create index(:user_sound_settings, [:sound_id])
    create unique_index(:user_sound_settings, [:user_id, :is_join_sound],
      where: "is_join_sound = 1",
      name: :user_sound_settings_join_sound_index
    )
    create unique_index(:user_sound_settings, [:user_id, :is_leave_sound],
      where: "is_leave_sound = 1",
      name: :user_sound_settings_leave_sound_index
    )

    execute """
    INSERT INTO user_sound_settings (user_id, sound_id, is_join_sound, is_leave_sound, inserted_at, updated_at)
    SELECT user_id, id, COALESCE(is_join_sound, 0), COALESCE(is_leave_sound, 0), datetime('now'), datetime('now')
    FROM sounds
    WHERE is_join_sound = 1 OR is_leave_sound = 1;
    """, """
    DELETE FROM user_sound_settings;
    """
  end
end
