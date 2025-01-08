defmodule Soundboard.Repo.Migrations.AddUserIdToSounds do
  use Ecto.Migration

  def change do
    alter table(:sounds) do
      add :user_id, references(:users, on_delete: :nilify_all)
    end
  end
end
