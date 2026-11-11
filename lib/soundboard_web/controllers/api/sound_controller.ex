defmodule SoundboardWeb.API.SoundController do
  @moduledoc """
  The JSON API. `SoundboardWeb.Plugs.APIAuth` has already authenticated the
  token's user and `SoundboardWeb.Plugs.Tenant` resolved the guild, so every
  action acts as `:current_user` in `:current_guild_id`.
  """

  use SoundboardWeb, :controller

  import Ecto.Query, only: [where: 2]

  alias Soundboard.{Repo, Sound, Sounds, UploadsPath}

  def index(conn, _params) do
    sounds =
      Sound
      |> Sound.with_tags()
      |> where(guild_id: ^guild_id(conn))
      |> Repo.all()
      |> Enum.map(&format_sound(&1, conn.assigns[:current_user]))

    json(conn, %{data: sounds})
  end

  def favorites(conn, _params) do
    user = conn.assigns.current_user

    sounds =
      Enum.map(
        Soundboard.Favorites.list_favorite_sounds_with_tags(user.id, guild_id(conn)),
        &format_sound(&1, user)
      )

    json(conn, %{data: sounds})
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    case create_sound(user, params, guild_id(conn)) do
      {:ok, sound} ->
        conn
        |> put_status(:created)
        |> json(%{data: format_sound(sound, user)})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def play(conn, %{"id" => id}) do
    case Repo.get_by(Sound, id: id, guild_id: guild_id(conn)) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Sound not found"})

      sound ->
        user = conn.assigns.current_user
        Soundboard.AudioPlayer.play_sound(sound.filename, user, guild_id(conn))

        conn
        |> put_status(:accepted)
        |> json(%{
          data: %{
            status: "accepted",
            message: "Playback request accepted for #{sound.filename}",
            requested_by: user.username,
            sound: %{id: sound.id, filename: sound.filename}
          }
        })
    end
  end

  def file(conn, %{"id" => id}) do
    case Repo.get_by(Sound, id: id, guild_id: guild_id(conn)) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Sound not found"})

      %Sound{source_type: "url", url: url} when is_binary(url) ->
        redirect(conn, external: url)

      sound ->
        path = UploadsPath.file_path(sound.storage_key || sound.filename)

        if File.regular?(path) do
          send_file(conn, 200, path)
        else
          conn
          |> put_status(:not_found)
          |> json(%{error: "Sound file missing"})
        end
    end
  end

  def stop(conn, _params) do
    Soundboard.AudioPlayer.stop_sound(guild_id(conn))

    conn
    |> put_status(:accepted)
    |> json(%{
      data: %{
        status: "accepted",
        message: "Stop request accepted"
      }
    })
  end

  defp create_sound(user, params, guild_id) do
    user
    |> Sounds.new_create_request(Map.put(params, "guild_id", guild_id))
    |> Sounds.create_sound()
  end

  defp guild_id(conn), do: conn.assigns.current_guild_id

  defp format_sound(sound, current_user) do
    user_setting = find_user_setting(sound, current_user)

    %{
      id: sound.id,
      filename: sound.filename,
      source_type: sound.source_type,
      url: sound.url,
      volume: sound.volume,
      description: sound.description,
      tags: Enum.map(sound.tags || [], & &1.name),
      is_join_sound: user_setting && user_setting.is_join_sound,
      is_leave_sound: user_setting && user_setting.is_leave_sound,
      inserted_at: sound.inserted_at,
      updated_at: sound.updated_at
    }
  end

  defp find_user_setting(sound, user) do
    settings =
      if Ecto.assoc_loaded?(sound.user_sound_settings) do
        sound.user_sound_settings
      else
        sound
        |> Repo.preload(:user_sound_settings)
        |> Map.get(:user_sound_settings)
      end

    Enum.find(settings, &(&1.user_id == user.id))
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key -> interpolation(opts, key) end)
    end)
  end

  defp interpolation(opts, key) do
    Enum.find_value(opts, key, fn {name, value} -> to_string(name) == key && to_string(value) end)
  end
end
