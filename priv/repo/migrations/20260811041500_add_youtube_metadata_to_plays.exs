defmodule Soundboard.Repo.Migrations.AddYoutubeMetadataToPlays do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :media_type, :string, null: false, default: "sound"
      add :youtube_id, :string
      add :source_url, :string
    end

    create index(:plays, [:media_type])
    create index(:plays, [:youtube_id])
  end
end
