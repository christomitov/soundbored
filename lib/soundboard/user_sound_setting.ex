defmodule Soundboard.UserSoundSetting do
  use Ecto.Schema
  import Ecto.Changeset

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
    |> unique_constraint([:user_id, :is_join_sound],
      name: :user_join_sound_index,
      message: "You already have a join sound set"
    )
    |> unique_constraint([:user_id, :is_leave_sound],
      name: :user_leave_sound_index,
      message: "You already have a leave sound set"
    )
  end
end
