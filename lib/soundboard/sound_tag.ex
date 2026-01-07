defmodule Soundboard.SoundTag do
  @moduledoc """
  The SoundTag module.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Soundboard.Accounts.Tenant
  alias Soundboard.{Repo, Sound, Tag}

  @primary_key false
  schema "sound_tags" do
    belongs_to :tenant, Tenant
    belongs_to :sound, Soundboard.Sound, primary_key: true
    belongs_to :tag, Soundboard.Tag, primary_key: true
    timestamps()
  end

  def changeset(sound_tag, attrs) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    sound_tag
    |> cast(attrs, [:sound_id, :tag_id, :tenant_id])
    |> ensure_tenant()
    |> validate_required([:sound_id, :tag_id, :tenant_id])
    |> assoc_constraint(:tenant)
    |> unique_constraint(:sound_id, name: :sound_tags_tenant_id_sound_id_tag_id_index)
    |> put_change(:inserted_at, now)
    |> put_change(:updated_at, now)
  end

  defp ensure_tenant(changeset) do
    case get_field(changeset, :tenant_id) do
      nil -> put_tenant_from_associations(changeset)
      _ -> changeset
    end
  end

  defp put_tenant_from_associations(changeset) do
    sound_id = get_field(changeset, :sound_id)

    if sound_id do
      case Repo.get(Sound, sound_id) do
        %Sound{tenant_id: tid} when not is_nil(tid) ->
          put_change(changeset, :tenant_id, tid)

        _ ->
          maybe_put_tenant_from_tag(changeset)
      end
    else
      maybe_put_tenant_from_tag(changeset)
    end
  end

  defp maybe_put_tenant_from_tag(changeset) do
    case get_field(changeset, :tag_id) do
      nil ->
        changeset

      tag_id ->
        case Repo.get(Tag, tag_id) do
          %Tag{tenant_id: tid} when not is_nil(tid) ->
            put_change(changeset, :tenant_id, tid)

          _ ->
            changeset
        end
    end
  end
end
