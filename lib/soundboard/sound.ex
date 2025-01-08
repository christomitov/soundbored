defmodule Soundboard.Sound do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Soundboard.Repo

  schema "sounds" do
    field :filename, :string
    field :description, :string
    belongs_to :user, Soundboard.Accounts.User

    many_to_many :tags, Soundboard.Tag,
      join_through: Soundboard.SoundTag,
      on_replace: :delete

    timestamps()
  end

  def changeset(sound, attrs) do
    sound
    |> cast(attrs, [:filename, :description, :user_id])
    |> validate_required([:filename])
    |> put_tags(attrs)
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

  def get_recent_uploads(limit \\ 10) do
    from(s in Soundboard.Sound,
      join: u in assoc(s, :user),
      order_by: [desc: s.inserted_at],
      limit: ^limit,
      select: {s.filename, u.username, s.inserted_at}
    )
    |> Repo.all()
  end
end
