defmodule Soundboard.Repo.Migrations.CreateTenants do
  use Ecto.Migration

  def change do
    create table(:tenants) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :plan, :string, null: false, default: "community"
      add :max_sounds, :integer
      add :max_users, :integer
      add :max_guilds, :integer
      add :billing_customer_id, :string
      add :billing_subscription_id, :string
      add :subscription_ends_at, :utc_datetime

      timestamps()
    end

    create unique_index(:tenants, [:slug])
  end
end
