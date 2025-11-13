defmodule Soundboard.Sound do
  @moduledoc """
  The Sound module.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Soundboard.Accounts.{Tenant, User}
  alias Soundboard.Repo

  schema "sounds" do
    field :filename, :string
    # New field for remote sounds
    field :url, :string
    # "local" or "url"
    field :source_type, :string, default: "local"
    field :description, :string
    field :volume, :float, default: 1.0
    belongs_to :tenant, Tenant
    belongs_to :user, Soundboard.Accounts.User
    has_many :user_sound_settings, Soundboard.UserSoundSetting

    many_to_many :tags, Soundboard.Tag,
      join_through: Soundboard.SoundTag,
      on_replace: :delete,
      unique: true

    timestamps()
  end

  def changeset(sound, attrs) do
    sound
    |> cast(attrs, [
      :filename,
      :url,
      :source_type,
      :description,
      :user_id,
      :volume,
      :tenant_id
    ])
    |> ensure_tenant_from_user()
    |> validate_required([:user_id, :tenant_id])
    |> validate_source_type()
    |> validate_volume()
    |> assoc_constraint(:tenant)
    |> unique_constraint(:filename, name: :sounds_tenant_id_filename_index)
    |> put_tags(attrs)
  end

  defp validate_source_type(changeset) do
    case get_field(changeset, :source_type) do
      "local" -> validate_required(changeset, [:filename])
      "url" -> validate_required(changeset, [:url])
      _ -> add_error(changeset, :source_type, "must be either 'local' or 'url'")
    end
  end

  defp put_tags(changeset, %{tags: tags}) when is_list(tags) do
    put_assoc(changeset, :tags, tags)
  end

  defp put_tags(changeset, _), do: changeset

  defp validate_volume(changeset) do
    changeset
    |> validate_number(:volume,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.5
    )
    |> case do
      %{changes: %{volume: volume}} = cs when is_nil(volume) ->
        put_change(cs, :volume, 1.0)

      cs ->
        cs
    end
  end

  def with_tags(query \\ __MODULE__) do
    from s in query,
      preload: [:tags]
  end

  def by_tag(query \\ __MODULE__, tag_name) do
    from s in query,
      join: t in assoc(s, :tags),
      where: t.name == ^tag_name
  end

  def list_files do
    __MODULE__
    |> with_tags()
    |> preload(:user_sound_settings)
    |> Repo.all()
  end

  def get_sound_id(filename) do
    # Get the sound record by filename and return its ID
    case Repo.get_by(__MODULE__, filename: filename) do
      nil -> nil
      sound -> sound.id
    end
  end

  def get_recent_uploads(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    from(s in Soundboard.Sound,
      join: u in User,
      on: s.user_id == u.id,
      select: {s.filename, u.username, s.inserted_at},
      order_by: [desc: s.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def update_sound(sound, attrs) do
    sound
    |> changeset(attrs)
    |> Repo.update()
  end

  def get_user_join_sound(user_id) do
    Repo.one(
      from uss in Soundboard.UserSoundSetting,
        join: s in __MODULE__,
        on: uss.sound_id == s.id,
        where: uss.user_id == ^user_id and uss.is_join_sound == true,
        select: s.filename
    )
  end

  def get_user_leave_sound(user_id) do
    Repo.one(
      from uss in Soundboard.UserSoundSetting,
        join: s in __MODULE__,
        on: uss.sound_id == s.id,
        where: uss.user_id == ^user_id and uss.is_leave_sound == true,
        select: s.filename
    )
  end

  def get_user_sounds_by_discord_id(discord_id) do
    Repo.one(
      from u in User,
        where: u.discord_id == ^to_string(discord_id),
        left_join: uss in Soundboard.UserSoundSetting,
        on: uss.user_id == u.id,
        left_join: s in __MODULE__,
        on: uss.sound_id == s.id and (uss.is_join_sound == true or uss.is_leave_sound == true),
        select: {u.id, s.filename, uss.is_join_sound, uss.is_leave_sound}
    )
  end

  # Get a sound with all its associations loaded
  def get_sound!(id) do
    __MODULE__
    |> Repo.get!(id)
    |> Repo.preload([
      :tags,
      :user,
      user_sound_settings: [user: []]
    ])
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
          %User{tenant_id: user_tenant_id} when not is_nil(user_tenant_id) ->
            put_change(changeset, :tenant_id, user_tenant_id)

          _ ->
            changeset
        end
    end
  end
end
