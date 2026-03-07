defmodule Soundboard.UserSoundSetting do
  @moduledoc """
  The UserSoundSetting module.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Soundboard.Repo

  schema "user_sound_settings" do
    belongs_to :user, Soundboard.Accounts.User
    belongs_to :sound, Soundboard.Sound
    field :is_join_sound, :boolean, default: false
    field :is_leave_sound, :boolean, default: false

    timestamps()
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:user_id, :sound_id, :is_join_sound, :is_leave_sound])
    |> validate_required([:user_id, :sound_id])
  end

  def clear_conflicting_settings(user_id, sound_id, is_join_sound, is_leave_sound) do
    maybe_clear_join_sound(user_id, sound_id, is_join_sound)
    maybe_clear_leave_sound(user_id, sound_id, is_leave_sound)
    :ok
  end

  defp maybe_clear_join_sound(user_id, sound_id, true) do
    from(uss in __MODULE__,
      where:
        uss.user_id == ^user_id and
          uss.sound_id != ^sound_id and
          uss.is_join_sound == true
    )
    |> Repo.update_all(set: [is_join_sound: false])

    :ok
  end

  defp maybe_clear_join_sound(_user_id, _sound_id, _is_join_sound), do: :ok

  defp maybe_clear_leave_sound(user_id, sound_id, true) do
    from(uss in __MODULE__,
      where:
        uss.user_id == ^user_id and
          uss.sound_id != ^sound_id and
          uss.is_leave_sound == true
    )
    |> Repo.update_all(set: [is_leave_sound: false])

    :ok
  end

  defp maybe_clear_leave_sound(_user_id, _sound_id, _is_leave_sound), do: :ok
end
