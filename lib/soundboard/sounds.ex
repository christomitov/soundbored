defmodule Soundboard.Sounds do
  @moduledoc """
  Sound domain context.
  """

  import Ecto.Query

  alias Soundboard.Accounts.User
  alias Soundboard.{Repo, Sound}
  alias Soundboard.Sounds.{Management, Uploads}
  alias Soundboard.Sounds.Uploads.CreateRequest

  @detailed_preloads [
    :tags,
    :user,
    user_sound_settings: [user: []]
  ]

  @spec list_files() :: [Sound.t()]
  def list_files do
    Sound
    |> Sound.with_tags()
    |> preload(:user_sound_settings)
    |> Repo.all()
  end

  @spec list_detailed() :: [Sound.t()]
  def list_detailed do
    Sound
    |> Repo.all()
    |> Repo.preload(@detailed_preloads)
    |> Enum.sort_by(&String.downcase(&1.filename))
  end

  @spec fetch_sound_id(String.t()) :: {:ok, integer()} | :error
  def fetch_sound_id(filename) when is_binary(filename) do
    case Repo.get_by(Sound, filename: filename) do
      nil -> :error
      sound -> {:ok, sound.id}
    end
  end

  def ids_by_filename([]), do: %{}

  @spec ids_by_filename([String.t()]) :: %{optional(String.t()) => integer()}
  def ids_by_filename(filenames) when is_list(filenames) do
    from(s in Sound, where: s.filename in ^filenames, select: {s.filename, s.id})
    |> Repo.all()
    |> Map.new()
  end

  @spec filename_taken?(String.t()) :: boolean()
  def filename_taken?(filename) when is_binary(filename) do
    Repo.exists?(from s in Sound, where: s.filename == ^filename)
  end

  @spec filename_taken_excluding?(String.t(), integer() | String.t()) :: boolean()
  def filename_taken_excluding?(filename, sound_id) do
    from(s in Sound, where: s.filename == ^filename and s.id != ^sound_id)
    |> Repo.exists?()
  end

  @spec filename_conflicts_across_extensions?(String.t(), [String.t()]) :: boolean()
  def filename_conflicts_across_extensions?(base_name, extensions) when is_list(extensions) do
    names = Enum.map(extensions, &(base_name <> &1))

    from(s in Sound, where: s.filename in ^names)
    |> Repo.exists?()
  end

  @spec fetch_filename_extension(term()) :: {:ok, String.t()} | :error
  def fetch_filename_extension(sound_id) do
    case Repo.get(Sound, sound_id) do
      %Sound{filename: filename} -> {:ok, Path.extname(filename)}
      _ -> :error
    end
  end

  @spec get_recent_uploads(keyword()) :: [{String.t(), String.t(), NaiveDateTime.t()}]
  def get_recent_uploads(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    from(s in Sound,
      join: u in User,
      on: s.user_id == u.id,
      select: {s.filename, u.username, s.inserted_at},
      order_by: [desc: s.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @spec get_user_join_sound(integer()) :: String.t() | nil
  def get_user_join_sound(user_id) do
    Repo.one(
      from uss in Soundboard.UserSoundSetting,
        join: s in Sound,
        on: uss.sound_id == s.id,
        where: uss.user_id == ^user_id and uss.is_join_sound == true,
        select: s.filename
    )
  end

  @spec get_user_leave_sound(integer()) :: String.t() | nil
  def get_user_leave_sound(user_id) do
    Repo.one(
      from uss in Soundboard.UserSoundSetting,
        join: s in Sound,
        on: uss.sound_id == s.id,
        where: uss.user_id == ^user_id and uss.is_leave_sound == true,
        select: s.filename
    )
  end

  @spec get_user_join_sound_by_discord_id(term()) :: String.t() | nil
  def get_user_join_sound_by_discord_id(discord_id) do
    Repo.one(
      from u in User,
        where: u.discord_id == ^to_string(discord_id),
        left_join: uss in Soundboard.UserSoundSetting,
        on: uss.user_id == u.id and uss.is_join_sound == true,
        left_join: s in Sound,
        on: s.id == uss.sound_id,
        select: s.filename,
        limit: 1
    )
  end

  @spec get_user_leave_sound_by_discord_id(term()) :: String.t() | nil
  def get_user_leave_sound_by_discord_id(discord_id) do
    Repo.one(
      from u in User,
        where: u.discord_id == ^to_string(discord_id),
        left_join: uss in Soundboard.UserSoundSetting,
        on: uss.user_id == u.id and uss.is_leave_sound == true,
        left_join: s in Sound,
        on: s.id == uss.sound_id,
        select: s.filename,
        limit: 1
    )
  end

  @spec get_user_sound_preferences_by_discord_id(term()) :: map() | nil
  def get_user_sound_preferences_by_discord_id(discord_id) do
    case Repo.get_by(User, discord_id: to_string(discord_id)) do
      nil ->
        nil

      user ->
        %{
          user_id: user.id,
          join_sound: get_user_join_sound(user.id),
          leave_sound: get_user_leave_sound(user.id)
        }
    end
  end

  @spec get_sound!(term()) :: Sound.t()
  def get_sound!(id) do
    Sound
    |> Repo.get!(id)
    |> Repo.preload(@detailed_preloads)
  end

  @spec update_sound(Sound.t(), map()) :: {:ok, Sound.t()} | {:error, Ecto.Changeset.t()}
  def update_sound(sound, attrs) do
    sound
    |> Sound.changeset(attrs)
    |> Repo.update()
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
