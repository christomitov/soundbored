defmodule Soundboard.Repo.Migrations.CreateUserSoundSettings do
  use Ecto.Migration

  def change do
    drop_if_exists index(:sounds, [:user_id, :is_join_sound], name: :user_join_sound_index)
    drop_if_exists index(:sounds, [:user_id, :is_leave_sound], name: :user_leave_sound_index)

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
      where: "is_join_sound = TRUE",
      name: :user_join_sound_index
    )
    create unique_index(:user_sound_settings, [:user_id, :is_leave_sound],
      where: "is_leave_sound = TRUE",
      name: :user_leave_sound_index
    )
  end
end
