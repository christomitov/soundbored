defmodule Soundboard.Repo.Migrations.AddGuildIdToPlays do
  use Ecto.Migration

  @moduledoc """
  Scopes plays to a guild so stats never mix servers.

  Plays are backfilled from their sound's guild. Plays whose sound was
  deleted fall back to the default guild, the same rule the sounds backfill
  used.
  """

  def up do
    alter table(:plays) do
      add :guild_id, :string
    end

    flush()

    execute """
    UPDATE plays
    SET guild_id = (SELECT guild_id FROM sounds WHERE sounds.id = plays.sound_id)
    WHERE sound_id IS NOT NULL
    """

    repo().query!("UPDATE plays SET guild_id = ? WHERE guild_id IS NULL", [
      Soundboard.Tenants.default_guild_id()
    ])

    create index(:plays, [:guild_id, :inserted_at])
  end

  def down do
    drop_if_exists index(:plays, [:guild_id, :inserted_at])

    alter table(:plays) do
      remove :guild_id
    end
  end
end
