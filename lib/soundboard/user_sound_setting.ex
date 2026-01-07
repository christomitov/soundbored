defmodule Soundboard.UserSoundSetting do
  @moduledoc """
  The UserSoundSetting module.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Soundboard.Accounts.{Tenant, User}
  alias Soundboard.Repo

  schema "user_sound_settings" do
    belongs_to :tenant, Tenant
    belongs_to :user, Soundboard.Accounts.User
    belongs_to :sound, Soundboard.Sound
    field :is_join_sound, :boolean, default: false
    field :is_leave_sound, :boolean, default: false

    timestamps()
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:user_id, :sound_id, :tenant_id, :is_join_sound, :is_leave_sound])
    |> ensure_tenant_from_user()
    |> validate_required([:user_id, :sound_id, :tenant_id])
    |> assoc_constraint(:tenant)
    |> clear_other_settings()
  end

  # Clear other settings when setting new join/leave sounds
  defp clear_other_settings(changeset) do
    case {get_field(changeset, :user_id), get_field(changeset, :sound_id)} do
      {user_id, sound_id} when not is_nil(user_id) and not is_nil(sound_id) ->
        changeset
        |> maybe_clear_join_sound(user_id, sound_id)
        |> maybe_clear_leave_sound(user_id, sound_id)

      _ ->
        changeset
    end
  end

  defp maybe_clear_join_sound(changeset, user_id, sound_id) do
    tenant_id = get_field(changeset, :tenant_id)

    case get_change(changeset, :is_join_sound) do
      true ->
        # Only clear other join sounds if we're setting this one as a join sound
        from(uss in __MODULE__,
          where:
            uss.user_id == ^user_id and
              uss.tenant_id == ^tenant_id and
              uss.sound_id != ^sound_id and
              uss.is_join_sound == true
        )
        |> Repo.update_all(set: [is_join_sound: false])

        changeset

      _ ->
        changeset
    end
  end

  defp maybe_clear_leave_sound(changeset, user_id, sound_id) do
    tenant_id = get_field(changeset, :tenant_id)

    case get_change(changeset, :is_leave_sound) do
      true ->
        # Only clear other leave sounds if we're setting this one as a leave sound
        from(uss in __MODULE__,
          where:
            uss.user_id == ^user_id and
              uss.tenant_id == ^tenant_id and
              uss.sound_id != ^sound_id and
              uss.is_leave_sound == true
        )
        |> Repo.update_all(set: [is_leave_sound: false])

        changeset

      _ ->
        changeset
    end
  end

  defp ensure_tenant_from_user(changeset) do
    tenant_id = get_field(changeset, :tenant_id)
    user_id = get_field(changeset, :user_id)

    cond do
      not is_nil(tenant_id) ->
        changeset

      is_nil(user_id) ->
        changeset

      true ->
        case Repo.get(User, user_id) do
          %User{tenant_id: tid} when not is_nil(tid) ->
            put_change(changeset, :tenant_id, tid)

          _ ->
            changeset
        end
    end
  end
end
