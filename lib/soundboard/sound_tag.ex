defmodule Soundboard.SoundTag do
  @moduledoc """
  The SoundTag module.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "sound_tags" do
    belongs_to :sound, Soundboard.Sound
    belongs_to :tag, Soundboard.Tag

    timestamps()
  end

  def changeset(sound_tag, attrs) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    sound_tag
    |> cast(attrs, [:sound_id, :tag_id])
    |> validate_required([:sound_id, :tag_id])
    |> unique_constraint([:sound_id, :tag_id])
    |> put_change(:inserted_at, now)
    |> put_change(:updated_at, now)
  end
end
