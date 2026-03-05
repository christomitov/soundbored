defmodule Soundboard.Repo.Migrations.CreateChains do
  use Ecto.Migration

  def change do
    create table(:chains) do
      add :name, :string, null: false
      add :is_public, :boolean, null: false, default: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:chains, [:user_id])
    create index(:chains, [:is_public])
    create unique_index(:chains, [:user_id, :name], name: :chains_user_id_name_index)

    create table(:chain_items) do
      add :position, :integer, null: false
      add :chain_id, references(:chains, on_delete: :delete_all), null: false
      add :sound_id, references(:sounds, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:chain_items, [:chain_id])
    create index(:chain_items, [:sound_id])

    create unique_index(:chain_items, [:chain_id, :position],
             name: :chain_items_chain_id_position_index
           )
  end
end
