defmodule Soundboard.Repo.Migrations.AddIndexToPlays do
  use Ecto.Migration

  def change do
    create index(:plays, [:inserted_at])
  end
end
