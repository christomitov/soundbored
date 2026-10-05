defmodule Soundboard.UserSoundSetting do
  @moduledoc """
  The UserSoundSetting module.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Soundboard.Repo

  schema "user_sound_settings" do
    field :guild_id, :string
    belongs_to :user, Soundboard.Accounts.User
    belongs_to :sound, Soundboard.Sound
    field :is_join_sound, :boolean, default: false
    field :is_leave_sound, :boolean, default: false

    timestamps()
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:user_id, :sound_id, :guild_id, :is_join_sound, :is_leave_sound])
    |> Soundboard.Tenants.put_default_guild_id()
    |> validate_required([:user_id, :sound_id])
  end

  def clear_conflicting_settings(
        user_id,
        sound_id,
        is_join_sound,
        is_leave_sound,
        guild_id \\ nil
      ) do
    guild_id = Soundboard.Tenants.scope_guild_id(guild_id)
    maybe_clear_join_sound(user_id, sound_id, is_join_sound, guild_id)
    maybe_clear_leave_sound(user_id, sound_id, is_leave_sound, guild_id)
    :ok
  end

  defp maybe_clear_join_sound(user_id, sound_id, true, guild_id) do
    from(uss in __MODULE__,
      join: s in Soundboard.Sound,
      on: uss.sound_id == s.id,
      where:
        uss.user_id == ^user_id and
          uss.sound_id != ^sound_id and
          uss.is_join_sound == true and
          s.guild_id == ^guild_id
    )
    |> Repo.update_all(set: [is_join_sound: false])

    :ok
  end

  defp maybe_clear_join_sound(_user_id, _sound_id, _is_join_sound, _guild_id), do: :ok

  defp maybe_clear_leave_sound(user_id, sound_id, true, guild_id) do
    from(uss in __MODULE__,
      join: s in Soundboard.Sound,
      on: uss.sound_id == s.id,
      where:
        uss.user_id == ^user_id and
          uss.sound_id != ^sound_id and
          uss.is_leave_sound == true and
          s.guild_id == ^guild_id
    )
    |> Repo.update_all(set: [is_leave_sound: false])

    :ok
  end

  defp maybe_clear_leave_sound(_user_id, _sound_id, _is_leave_sound, _guild_id), do: :ok
end
