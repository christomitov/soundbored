defmodule Soundboard.Repo.Migrations.CreateSounds do
  use Ecto.Migration

  def change do
    create table(:sounds) do
      add :filename, :string, null: false
      add :tags, {:array, :string}, default: []
      add :description, :text

      timestamps()
    end

    create unique_index(:sounds, [:filename])
  end
end
