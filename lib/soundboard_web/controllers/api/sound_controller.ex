defmodule SoundboardWeb.API.SoundController do
  use SoundboardWeb, :controller

  alias Soundboard.{Repo, Sound}
  alias Soundboard.Sounds.Uploads

  def index(conn, _params) do
    sounds =
      Sound
      |> Sound.with_tags()
      |> Repo.all()
      |> Enum.map(&format_sound/1)

    json(conn, %{data: sounds})
  end

  def create(conn, params) do
    with {:ok, user} <- require_upload_user(conn),
         {:ok, sound} <- create_sound(user, params) do
      conn
      |> put_status(:created)
      |> json(%{data: format_sound(sound, user)})
    else
      {:error, :forbidden_auth_state} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Uploads require a user API token"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def play(conn, %{"id" => id}) do
    case Repo.get(Sound, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Sound not found"})

      sound ->
        username =
          case conn.assigns[:current_user] do
            %Soundboard.Accounts.User{username: uname} -> uname
            _ -> get_req_header(conn, "x-username") |> List.first() || "API User"
          end

        Soundboard.AudioPlayer.play_sound(sound.filename, username)

        json(conn, %{
          status: "success",
          message: "Playing sound: #{sound.filename}",
          played_by: username
        })
    end
  end

  def stop(conn, _params) do
    Soundboard.AudioPlayer.stop_sound()

    json(conn, %{
      status: "success",
      message: "Stopped all sounds"
    })
  end

  defp create_sound(user, params) do
    params
    |> Uploads.build_create_request(user)
    |> Uploads.create()
  end

  defp require_upload_user(conn) do
    case conn.assigns[:current_user] do
      %Soundboard.Accounts.User{} = user -> {:ok, user}
      _ -> {:error, :forbidden_auth_state}
    end
  end

  defp format_sound(sound, current_user \\ nil) do
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

  defp find_user_setting(_sound, nil), do: nil

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
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts
        |> Keyword.get(String.to_existing_atom(key), key)
        |> to_string()
      end)
    end)
  end
end
