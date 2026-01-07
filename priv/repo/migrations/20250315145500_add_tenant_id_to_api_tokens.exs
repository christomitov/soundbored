defmodule Soundboard.Repo.Migrations.AddTenantIdToApiTokens do
  use Ecto.Migration

  def up do
    ensure_default_tenant()

    alter table(:api_tokens) do
      add :tenant_id, references(:tenants, on_delete: :delete_all)
    end

    backfill_from_users()
    backfill_default_tenant()
    enforce_not_null_for_supported_adapters()

    create index(:api_tokens, [:tenant_id])
  end

  def down do
    drop_if_exists index(:api_tokens, [:tenant_id])

    alter table(:api_tokens) do
      remove :tenant_id
    end
  end

  defp ensure_default_tenant do
    execute("""
    INSERT INTO tenants (name, slug, plan, inserted_at, updated_at)
    SELECT 'Default Tenant', 'default', 'community', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    WHERE NOT EXISTS (SELECT 1 FROM tenants WHERE slug = 'default')
    """)
  end

  defp backfill_from_users do
    execute("""
    UPDATE api_tokens
    SET tenant_id = users.tenant_id
    FROM users
    WHERE api_tokens.user_id = users.id AND api_tokens.tenant_id IS NULL
    """)
  end

  defp backfill_default_tenant do
    execute("""
    UPDATE api_tokens
    SET tenant_id = tenants.id
    FROM tenants
    WHERE tenants.slug = 'default' AND api_tokens.tenant_id IS NULL
    """)
  end

  defp enforce_not_null_for_supported_adapters do
    unless sqlite?() do
      execute("ALTER TABLE api_tokens ALTER COLUMN tenant_id SET NOT NULL")
    end
  end

  defp sqlite? do
    repo().config()[:adapter] in [Ecto.Adapters.SQLite3, Ecto.Adapters.Exqlite]
  end
end
