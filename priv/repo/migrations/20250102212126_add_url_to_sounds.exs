defmodule Soundboard.Repo.Migrations.AddUrlToSounds do
  use Ecto.Migration

  def change do
    alter table(:sounds) do
      add :url, :string
      add :source_type, :string, default: "local", null: false
    end
  end
end
