defmodule Soundboard.Repo.Migrations.AddJoinLeaveFlagsToSounds do
  use Ecto.Migration

  def change do
    alter table(:sounds) do
      add :is_join_sound, :boolean, default: false
      add :is_leave_sound, :boolean, default: false
    end

    # Ensure only one join and one leave sound per user
    create unique_index(:sounds, [:user_id, :is_join_sound],
      name: :user_join_sound_index,
      where: "is_join_sound = TRUE"  # Use proper SQL boolean
    )
    create unique_index(:sounds, [:user_id, :is_leave_sound],
      name: :user_leave_sound_index,
      where: "is_leave_sound = TRUE"  # Use proper SQL boolean
    )
  end
end
