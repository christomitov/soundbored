defmodule Soundboard.Sounds do
  @moduledoc """
  Sound domain context.
  """

  import Ecto.Query

  alias Soundboard.Accounts.User
  alias Soundboard.{Repo, Sound, Tenants}
  alias Soundboard.Sounds.{Management, Uploads}
  alias Soundboard.Sounds.Uploads.CreateRequest

  @detailed_preloads [
    :tags,
    :user,
    user_sound_settings: [user: []]
  ]

  @spec list_detailed(String.t() | nil) :: [Sound.t()]
  def list_detailed(guild_id \\ nil) do
    Sound
    |> where(guild_id: ^Tenants.scope_guild_id(guild_id))
    |> Repo.all()
    |> Repo.preload(@detailed_preloads)
    |> Enum.sort_by(&String.downcase(&1.filename))
  end

  @spec fetch_sound_id(String.t(), String.t() | nil) :: {:ok, integer()} | :error
  def fetch_sound_id(filename, guild_id \\ nil) when is_binary(filename) do
    case Repo.get_by(Sound, filename: filename, guild_id: Tenants.scope_guild_id(guild_id)) do
      nil -> :error
      sound -> {:ok, sound.id}
    end
  end

  @spec ids_by_filename([String.t()], String.t() | nil) :: %{optional(String.t()) => integer()}
  def ids_by_filename(filenames, guild_id \\ nil)

  def ids_by_filename([], _guild_id), do: %{}

  def ids_by_filename(filenames, guild_id) when is_list(filenames) do
    from(s in Sound,
      where: s.filename in ^filenames and s.guild_id == ^Tenants.scope_guild_id(guild_id),
      select: {s.filename, s.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  @spec filename_taken_excluding?(String.t(), integer() | String.t(), String.t() | nil) ::
          boolean()
  def filename_taken_excluding?(filename, sound_id, guild_id \\ nil) do
    Repo.exists?(
      from(s in Sound,
        where:
          s.filename == ^filename and s.id != ^sound_id and
            s.guild_id == ^Tenants.scope_guild_id(guild_id)
      )
    )
  end

  @spec get_recent_uploads(keyword()) :: [{String.t(), String.t(), NaiveDateTime.t()}]
  def get_recent_uploads(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    Repo.all(
      from(s in Sound,
        join: u in User,
        on: s.user_id == u.id,
        where: s.guild_id == ^Tenants.scope_guild_id(Keyword.get(opts, :guild_id)),
        select: {s.filename, u.username, s.inserted_at},
        order_by: [desc: s.inserted_at, desc: s.id],
        limit: ^limit
      )
    )
  end

  @spec get_user_join_sound_by_discord_id(term(), String.t() | nil) :: String.t() | nil
  def get_user_join_sound_by_discord_id(discord_id, guild_id \\ nil),
    do: sound_by_discord_id(discord_id, guild_id, :is_join_sound)

  @spec get_user_leave_sound_by_discord_id(term(), String.t() | nil) :: String.t() | nil
  def get_user_leave_sound_by_discord_id(discord_id, guild_id \\ nil),
    do: sound_by_discord_id(discord_id, guild_id, :is_leave_sound)

  defp sound_by_discord_id(discord_id, guild_id, flag) do
    Repo.one(
      from u in User,
        join: uss in Soundboard.UserSoundSetting,
        on: uss.user_id == u.id and field(uss, ^flag) == true,
        join: s in Sound,
        on: s.id == uss.sound_id,
        where:
          u.discord_id == ^to_string(discord_id) and
            s.guild_id == ^Tenants.scope_guild_id(guild_id),
        select: s.filename,
        limit: 1
    )
  end

  @spec fetch_sound(term(), String.t() | nil) :: {:ok, Sound.t()} | :error
  def fetch_sound(id, guild_id) do
    with {:ok, id} <- Ecto.Type.cast(:id, id),
         %Sound{} = sound <-
           Repo.get_by(Sound, id: id, guild_id: Tenants.scope_guild_id(guild_id)) do
      {:ok, Repo.preload(sound, @detailed_preloads)}
    else
      _ -> :error
    end
  end

  @spec update_sound(Sound.t(), integer(), map()) :: {:ok, Sound.t()} | {:error, term()}
  def update_sound(sound, user_id, params), do: Management.update_sound(sound, user_id, params)

  @spec delete_sound(Sound.t(), integer()) :: :ok | {:error, term()}
  def delete_sound(sound, user_id), do: Management.delete_sound(sound, user_id)

  @spec new_create_request(User.t() | nil, map()) :: CreateRequest.t()
  def new_create_request(user, attrs), do: CreateRequest.new(user, attrs)

  @spec put_request_upload(CreateRequest.t(), map() | nil) :: CreateRequest.t()
  def put_request_upload(request, upload), do: CreateRequest.put_upload(request, upload)

  @spec validate_create(CreateRequest.t()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def validate_create(request), do: Uploads.validate(request)

  @spec create_sound(CreateRequest.t()) :: {:ok, Sound.t()} | {:error, Ecto.Changeset.t()}
  def create_sound(request), do: Uploads.create(request)

  @spec create_error_message(Ecto.Changeset.t() | String.t() | term()) :: String.t()
  def create_error_message(error), do: Uploads.error_message(error)
end
