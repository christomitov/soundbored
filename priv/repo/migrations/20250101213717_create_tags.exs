defmodule Soundboard.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags) do
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:tags, [:name])

    create table(:sound_tags) do
      add :sound_id, references(:sounds, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:sound_tags, [:sound_id, :tag_id])
  end
end
