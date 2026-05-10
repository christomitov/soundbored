defmodule Soundboard.Repo.Migrations.RemoveTokenPlainFromApiTokens do
  use Ecto.Migration

  def up do
    alter table(:api_tokens) do
      remove :token
    end
  end

  def down do
    alter table(:api_tokens) do
      add :token, :string, null: false, default: ""
    end
  end
end
