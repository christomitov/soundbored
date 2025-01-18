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
    field :is_join_sound, :boolean, default: false
    field :is_leave_sound, :boolean, default: false
    belongs_to :user, Soundboard.Accounts.User

    many_to_many :tags, Soundboard.Tag,
      join_through: Soundboard.SoundTag,
      on_replace: :delete

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
      :is_join_sound,
      :is_leave_sound
    ])
    |> validate_required([:user_id])
    |> validate_source_type()
    |> unique_constraint(:filename, name: :sounds_filename_index)
    |> unique_constraint([:user_id, :is_join_sound],
      name: :user_join_sound_index,
      message: "You already have a join sound set"
    )
    |> unique_constraint([:user_id, :is_leave_sound],
      name: :user_leave_sound_index,
      message: "You already have a leave sound set"
    )
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
    # Get all sounds from the database with their tags
    with_tags()
    |> Soundboard.Repo.all()
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
end
