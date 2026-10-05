defmodule Soundboard.Repo.Migrations.AddGuildIdToSounds do
  use Ecto.Migration

  @moduledoc """
  Adds guild scoping to sounds and per-user sound settings.

  Existing rows are backfilled into the default guild so single-guild
  deployments keep working unchanged. The global unique filename index is
  replaced with a per-guild composite index so different servers can use the
  same sound names.
  """

  def up do
    alter table(:sounds) do
      add :guild_id, :string
      add :byte_size, :integer, default: 0
    end

    alter table(:user_sound_settings) do
      add :guild_id, :string
    end

    flush()

    default_guild = Soundboard.Tenants.default_guild_id()

    repo().query!("UPDATE sounds SET guild_id = ?", [default_guild])

    execute """
            UPDATE user_sound_settings
            SET guild_id = (SELECT guild_id FROM sounds WHERE sounds.id = user_sound_settings.sound_id)
            WHERE guild_id IS NULL
            """,
            "UPDATE user_sound_settings SET guild_id = NULL"

    drop_if_exists index(:sounds, [:filename])

    create unique_index(:sounds, [:guild_id, :filename])

    # The original migration created these with custom names; drop both the
    # custom-named and default-named variants.
    drop_if_exists index(:user_sound_settings, [:user_id, :is_join_sound],
                     name: :user_sound_settings_join_sound_index
                   )

    drop_if_exists index(:user_sound_settings, [:user_id, :is_join_sound])

    drop_if_exists index(:user_sound_settings, [:user_id, :is_leave_sound],
                     name: :user_sound_settings_leave_sound_index
                   )

    drop_if_exists index(:user_sound_settings, [:user_id, :is_leave_sound])

    create unique_index(:user_sound_settings, [:user_id, :guild_id, :is_join_sound],
             where: "is_join_sound = 1"
           )

    create unique_index(:user_sound_settings, [:user_id, :guild_id, :is_leave_sound],
             where: "is_leave_sound = 1"
           )
  end

  def down do
    drop_if_exists index(:user_sound_settings, [:user_id, :guild_id, :is_join_sound])
    drop_if_exists index(:user_sound_settings, [:user_id, :guild_id, :is_leave_sound])

    create unique_index(:user_sound_settings, [:user_id, :is_join_sound],
             where: "is_join_sound = 1",
             name: :user_sound_settings_join_sound_index
           )

    create unique_index(:user_sound_settings, [:user_id, :is_leave_sound],
             where: "is_leave_sound = 1",
             name: :user_sound_settings_leave_sound_index
           )

    drop_if_exists index(:sounds, [:guild_id, :filename])
    drop_if_exists index(:sounds, [:filename])

    # Non-unique: after multi-tenant use, different guilds may share filenames,
    # and a rollback must never lose data.
    create index(:sounds, [:filename])

    alter table(:user_sound_settings) do
      remove :guild_id
    end

    alter table(:sounds) do
      remove :byte_size
      remove :guild_id
    end
  end
end
