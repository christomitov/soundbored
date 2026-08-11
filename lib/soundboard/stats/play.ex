defmodule Soundboard.Stats.Play do
  @moduledoc """
  The Play module.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Soundboard.Accounts.User
  alias Soundboard.Sound

  schema "plays" do
    field :played_filename, :string
    field :media_type, :string, default: "sound"
    field :youtube_id, :string
    field :source_url, :string
    belongs_to :sound, Sound
    belongs_to :user, User

    timestamps()
  end

  def changeset(play, attrs) do
    play
    |> cast(attrs, [
      :played_filename,
      :media_type,
      :youtube_id,
      :source_url,
      :sound_id,
      :user_id
    ])
    |> validate_required([:played_filename, :media_type, :user_id])
    |> validate_inclusion(:media_type, ["sound", "youtube"])
    |> validate_media_fields()
    |> assoc_constraint(:sound)
  end

  defp validate_media_fields(changeset) do
    case get_field(changeset, :media_type) do
      "youtube" -> validate_required(changeset, [:youtube_id, :source_url])
      _ -> validate_required(changeset, [:sound_id])
    end
  end
end
