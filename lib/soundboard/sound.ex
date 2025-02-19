defmodule Soundboard.Sound do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Soundboard.Repo
  alias Soundboard.Accounts.User

  schema "sounds" do
    field :filename, :string
    # New field for remote sounds
    field :url, :string
    # "local" or "url"
    field :source_type, :string, default: "local"
    field :description, :string
    belongs_to :user, Soundboard.Accounts.User
    has_many :user_sound_settings, Soundboard.UserSoundSetting

    many_to_many :tags, Soundboard.Tag, join_through: "sound_tags"

    timestamps()
  end

  def changeset(sound, attrs) do
    sound
    |> cast(attrs, [
      :filename,
      :url,
      :source_type,
      :description,
      :user_id
    ])
    |> validate_required([:user_id])
    |> validate_source_type()
    |> unique_constraint(:filename, name: :sounds_filename_index)
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
      from s in __MODULE__,
        where: s.user_id == ^user_id and s.is_join_sound == true,
        select: s.filename
    )
  end

  def get_user_leave_sound(user_id) do
    Repo.one(
      from s in __MODULE__,
        where: s.user_id == ^user_id and s.is_leave_sound == true,
        select: s.filename
    )
  end

  def get_user_sounds_by_discord_id(discord_id) do
    Repo.one(
      from u in User,
        where: u.discord_id == ^to_string(discord_id),
        left_join: s in __MODULE__,
        on: s.user_id == u.id and (s.is_join_sound == true or s.is_leave_sound == true),
        select: {u.id, s.filename, s.is_join_sound, s.is_leave_sound}
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
end
