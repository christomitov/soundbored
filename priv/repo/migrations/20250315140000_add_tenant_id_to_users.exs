defmodule Soundboard.Repo.Migrations.AddTenantIdToUsers do
  use Ecto.Migration

  def up do
    ensure_default_tenant()

    drop_if_exists unique_index(:users, [:discord_id])

    alter table(:users) do
      add :tenant_id, references(:tenants, on_delete: :delete_all)
    end

    backfill_default_tenant()
    enforce_not_null_for_supported_adapters()

    create index(:users, [:tenant_id])
    create unique_index(:users, [:tenant_id, :discord_id])
  end

  def down do
    drop_if_exists unique_index(:users, [:tenant_id, :discord_id])
    drop_if_exists index(:users, [:tenant_id])

    alter table(:users) do
      remove :tenant_id
    end

    create unique_index(:users, [:discord_id])
  end

  defp ensure_default_tenant do
    execute("""
    INSERT INTO tenants (name, slug, plan, inserted_at, updated_at)
    SELECT 'Default Tenant', 'default', 'community', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    WHERE NOT EXISTS (SELECT 1 FROM tenants WHERE slug = 'default')
    """)
  end

  defp backfill_default_tenant do
    execute("""
    UPDATE users
    SET tenant_id = tenants.id
    FROM tenants
    WHERE tenants.slug = 'default' AND users.tenant_id IS NULL
    """)
  end

  defp enforce_not_null_for_supported_adapters do
    unless sqlite?() do
      execute("ALTER TABLE users ALTER COLUMN tenant_id SET NOT NULL")
    end
  end

  defp sqlite? do
    repo().config()[:adapter] in [Ecto.Adapters.SQLite3, Ecto.Adapters.Exqlite]
  end
end
