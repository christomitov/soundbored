defmodule Soundboard.Repo.Migrations.AddTenantIdToTags do
  use Ecto.Migration

  def up do
    ensure_default_tenant()

    drop_if_exists unique_index(:tags, [:name])

    alter table(:tags) do
      add :tenant_id, references(:tenants, on_delete: :delete_all)
    end

    backfill_default_tenant()
    enforce_not_null_for_supported_adapters()

    create index(:tags, [:tenant_id])
    create unique_index(:tags, [:tenant_id, :name])
  end

  def down do
    drop_if_exists unique_index(:tags, [:tenant_id, :name])
    drop_if_exists index(:tags, [:tenant_id])

    alter table(:tags) do
      remove :tenant_id
    end

    create unique_index(:tags, [:name])
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
    UPDATE tags
    SET tenant_id = tenants.id
    FROM tenants
    WHERE tenants.slug = 'default' AND tags.tenant_id IS NULL
    """)
  end

  defp enforce_not_null_for_supported_adapters do
    unless sqlite?() do
      execute("ALTER TABLE tags ALTER COLUMN tenant_id SET NOT NULL")
    end
  end

  defp sqlite? do
    repo().config()[:adapter] in [Ecto.Adapters.SQLite3, Ecto.Adapters.Exqlite]
  end
end
