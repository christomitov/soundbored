defmodule Soundboard.Repo.Migrations.CreateGuilds do
  use Ecto.Migration

  @default_storage_bytes 2_147_483_648

  def up do
    create table(:guilds) do
      add :discord_guild_id, :string, null: false
      add :slug, :string, null: false
      add :name, :string
      add :max_storage_bytes, :integer

      timestamps()
    end

    create unique_index(:guilds, [:discord_guild_id])
    create unique_index(:guilds, [:slug])

    flush()

    default_cap =
      Application.get_env(:soundboard, :default_storage_bytes) || @default_storage_bytes

    repo().query!(
      "UPDATE guilds SET max_storage_bytes = ? WHERE max_storage_bytes IS NULL",
      [default_cap]
    )
  end

  def down do
    drop table(:guilds)
  end
end
