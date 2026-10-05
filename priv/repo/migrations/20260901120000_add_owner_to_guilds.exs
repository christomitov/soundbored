defmodule Soundboard.Repo.Migrations.AddOwnerToGuilds do
  use Ecto.Migration

  def change do
    alter table(:guilds) do
      add :owner_discord_id, :string
    end
  end
end
