defmodule Soundboard.Repo.Migrations.AddTokenPlainToApiTokens do
  use Ecto.Migration

  def change do
    alter table(:api_tokens) do
      add :token, :string, null: false, default: ""
    end
  end
end
