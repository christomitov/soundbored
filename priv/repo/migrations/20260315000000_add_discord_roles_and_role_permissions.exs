defmodule Soundboard.Repo.Migrations.AddDiscordRolesAndRolePermissions do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :discord_roles, :string
    end

    create table(:discord_role_settings) do
      add :guild_id, :string, null: false
      add :role_id, :string, null: false
      add :cooldown_ms, :integer, default: 0, null: false
      add :can_upload, :boolean, default: true, null: false
      add :can_play, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:discord_role_settings, [:guild_id, :role_id])
    create index(:discord_role_settings, [:guild_id])
    create index(:discord_role_settings, [:role_id])
  end
end
