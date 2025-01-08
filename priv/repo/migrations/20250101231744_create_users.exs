defmodule Soundboard.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :discord_id, :string, null: false
      add :username, :string, null: false
      add :avatar, :string

      timestamps()
    end

    create unique_index(:users, [:discord_id])
  end
end
