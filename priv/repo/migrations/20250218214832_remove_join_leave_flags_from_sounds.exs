defmodule Soundboard.Repo.Migrations.RemoveJoinLeaveFlagsFromSounds do
  use Ecto.Migration

  def change do
    alter table(:sounds) do
      remove :is_join_sound
      remove :is_leave_sound
    end
  end
end
