defmodule Soundboard.Repo.Migrations.CreateFavorites do
  use Ecto.Migration

  def change do
    create table(:favorites) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :filename, :string, null: false

      timestamps()
    end

    create unique_index(:favorites, [:user_id, :filename])
  end
end
