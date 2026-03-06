defmodule Soundboard.Favorites do
  @moduledoc """
  The Favorites module.
  """
  import Ecto.Query
  alias Soundboard.{Favorites.Favorite, Repo, Sound}

  @max_favorites 16

  def list_favorites(user_id) do
    Favorite
    |> where([f], f.user_id == ^user_id)
    |> select([f], f.sound_id)
    |> Repo.all()
  end

  def list_favorite_sounds_with_tags(user_id) do
    favorite_ids_query =
      Favorite
      |> where([f], f.user_id == ^user_id)
      |> select([f], f.sound_id)

    Sound.with_tags()
    |> where([s], s.id in subquery(favorite_ids_query))
    |> order_by([s], asc: fragment("lower(?)", s.filename))
    |> Repo.all()
  end

  def toggle_favorite(user_id, sound_id) do
    case Repo.get_by(Favorite, user_id: user_id, sound_id: sound_id) do
      nil -> add_favorite(user_id, sound_id)
      favorite -> Repo.delete(favorite)
    end
  end

  defp add_favorite(user_id, sound_id) do
    case Repo.get(Sound, sound_id) do
      nil ->
        {:error,
         Ecto.Changeset.add_error(Ecto.Changeset.change(%Favorite{}), :sound, "does not exist")}

      _sound ->
        # Check if user has reached max favorites
        count = Repo.one(from f in Favorite, where: f.user_id == ^user_id, select: count())

        if count >= @max_favorites do
          {:error, "You can only have #{@max_favorites} favorites"}
        else
          %Favorite{}
          |> Favorite.changeset(%{user_id: user_id, sound_id: sound_id})
          |> Repo.insert()
        end
    end
  end

  def favorite?(user_id, sound_id) do
    Repo.exists?(from f in Favorite, where: f.user_id == ^user_id and f.sound_id == ^sound_id)
  end

  def max_favorites, do: @max_favorites
end
