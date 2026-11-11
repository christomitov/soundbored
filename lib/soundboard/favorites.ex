defmodule Soundboard.Favorites do
  @moduledoc """
  The Favorites module.
  """

  import Ecto.Query

  alias Soundboard.Favorites.Favorite
  alias Soundboard.{Repo, Sound, Tenants}

  @type favorite_result :: {:ok, Soundboard.Favorites.Favorite.t()} | {:error, Ecto.Changeset.t()}

  @max_favorites 16

  @spec list_favorites(integer(), String.t() | nil) :: [integer()]
  def list_favorites(user_id, guild_id \\ nil) do
    user_id
    |> in_guild(guild_id)
    |> select([f], f.sound_id)
    |> Repo.all()
  end

  @spec list_favorite_sounds_with_tags(integer(), String.t() | nil) :: [Sound.t()]
  def list_favorite_sounds_with_tags(user_id, guild_id \\ nil) do
    favorite_ids_query = select(in_guild(user_id, guild_id), [f], f.sound_id)

    Sound.with_tags()
    |> where([s], s.id in subquery(favorite_ids_query))
    |> order_by([s], asc: fragment("lower(?)", s.filename))
    |> Repo.all()
  end

  @spec toggle_favorite(integer(), term(), String.t() | nil) :: favorite_result()
  def toggle_favorite(user_id, sound_id, guild_id \\ nil) do
    with {:ok, sound} <- fetch_sound(sound_id, guild_id) do
      case Repo.get_by(Favorite, user_id: user_id, sound_id: sound.id) do
        nil -> add_favorite(user_id, sound)
        favorite -> Repo.delete(favorite)
      end
    end
  end

  @spec error_message(Ecto.Changeset.t()) :: String.t()
  def error_message(%Ecto.Changeset{} = changeset) do
    Enum.map_join(changeset.errors, ", ", fn
      {:base, {msg, _}} -> msg
      {:sound, {"does not exist", _}} -> "Sound does not exist"
      {field, {msg, _}} -> "#{field} #{msg}"
    end)
  end

  defp add_favorite(user_id, sound) do
    count = Repo.one(select(in_guild(user_id, sound.guild_id), [f], count()))

    if count >= @max_favorites do
      {:error,
       Ecto.Changeset.add_error(
         Ecto.Changeset.change(%Favorite{}),
         :base,
         "You can only have #{@max_favorites} favorites"
       )}
    else
      %Favorite{}
      |> Favorite.changeset(%{user_id: user_id, sound_id: sound.id})
      |> Repo.insert()
    end
  end

  defp fetch_sound(sound_id, guild_id) do
    with {:ok, id} <- Ecto.Type.cast(:id, sound_id),
         %Sound{} = sound <-
           Repo.get_by(Sound, id: id, guild_id: Tenants.scope_guild_id(guild_id)) do
      {:ok, sound}
    else
      _ ->
        {:error,
         Ecto.Changeset.add_error(Ecto.Changeset.change(%Favorite{}), :sound, "does not exist")}
    end
  end

  defp in_guild(user_id, guild_id) do
    from f in Favorite,
      join: s in Sound,
      on: s.id == f.sound_id,
      where: f.user_id == ^user_id and s.guild_id == ^Tenants.scope_guild_id(guild_id)
  end

  @spec favorite?(integer(), integer()) :: boolean()
  def favorite?(user_id, sound_id) do
    Repo.exists?(from f in Favorite, where: f.user_id == ^user_id and f.sound_id == ^sound_id)
  end

  @spec max_favorites() :: pos_integer()
  def max_favorites, do: @max_favorites
end
