defmodule Soundboard.Repo.Migrations.CreateGuilds do
  use Ecto.Migration

  def change do
    create table(:guilds) do
      add :discord_guild_id, :string, null: false
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:guilds, [:discord_guild_id])
    create index(:guilds, [:tenant_id])
  end
end
