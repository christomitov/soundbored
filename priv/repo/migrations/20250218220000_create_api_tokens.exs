defmodule Soundboard.Repo.Migrations.CreateApiTokens do
  use Ecto.Migration

  def change do
    create table(:api_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token_hash, :string, null: false
      add :label, :string
      add :revoked_at, :naive_datetime
      add :last_used_at, :naive_datetime

      timestamps()
    end

    create unique_index(:api_tokens, [:token_hash])
    create index(:api_tokens, [:user_id])
  end
end
