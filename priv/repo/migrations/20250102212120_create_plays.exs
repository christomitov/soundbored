defmodule Soundboard.Repo.Migrations.CreatePlays do
  use Ecto.Migration

  def change do
    create table(:plays) do
      add :sound_name, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:plays, [:user_id])
    create index(:plays, [:sound_name])
  end
end
