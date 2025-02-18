defmodule Soundboard.Repo.Migrations.RemoveJoinLeaveFlagsFromSounds do
  use Ecto.Migration

  def change do
    drop_if_exists index(:sounds, [:is_join_sound], name: :user_join_sound_index)
    drop_if_exists index(:sounds, [:is_leave_sound], name: :user_leave_sound_index)

    alter table(:sounds) do
      remove :is_join_sound
      remove :is_leave_sound
    end
  end
end
