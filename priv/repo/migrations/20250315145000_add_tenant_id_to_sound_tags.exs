defmodule Soundboard.Repo.Migrations.AddTenantIdToSoundTags do
  use Ecto.Migration

  def up do
    ensure_default_tenant()

    drop_if_exists unique_index(:sound_tags, [:sound_id, :tag_id])

    alter table(:sound_tags) do
      add :tenant_id, references(:tenants, on_delete: :delete_all)
    end

    backfill_from_sounds()
    backfill_default_tenant()
    enforce_not_null_for_supported_adapters()

    create index(:sound_tags, [:tenant_id])
    create unique_index(:sound_tags, [:tenant_id, :sound_id, :tag_id])
  end

  def down do
    drop_if_exists unique_index(:sound_tags, [:tenant_id, :sound_id, :tag_id])
    drop_if_exists index(:sound_tags, [:tenant_id])

    alter table(:sound_tags) do
      remove :tenant_id
    end

    create unique_index(:sound_tags, [:sound_id, :tag_id])
  end

  defp ensure_default_tenant do
    execute("""
    INSERT INTO tenants (name, slug, plan, inserted_at, updated_at)
    SELECT 'Default Tenant', 'default', 'community', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    WHERE NOT EXISTS (SELECT 1 FROM tenants WHERE slug = 'default')
    """)
  end

  defp backfill_from_sounds do
    execute("""
    UPDATE sound_tags
    SET tenant_id = sounds.tenant_id
    FROM sounds
    WHERE sound_tags.sound_id = sounds.id AND sound_tags.tenant_id IS NULL
    """)
  end

  defp backfill_default_tenant do
    execute("""
    UPDATE sound_tags
    SET tenant_id = tenants.id
    FROM tenants
    WHERE tenants.slug = 'default' AND sound_tags.tenant_id IS NULL
    """)
  end

  defp enforce_not_null_for_supported_adapters do
    unless sqlite?() do
      execute("ALTER TABLE sound_tags ALTER COLUMN tenant_id SET NOT NULL")
    end
  end

  defp sqlite? do
    repo().config()[:adapter] in [Ecto.Adapters.SQLite3, Ecto.Adapters.Exqlite]
  end
end
