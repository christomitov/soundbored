defmodule SoundboardWeb.API.SoundController do
  use SoundboardWeb, :controller

  alias Soundboard.{Repo, Sound}

  def index(conn, _params) do
    sounds =
      Sound
      |> Sound.with_tags()
      |> Repo.all()
      |> Enum.map(&format_sound/1)

    json(conn, %{data: sounds})
  end

  def play(conn, %{"id" => id}) do
    case Repo.get(Sound, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Sound not found"})

      sound ->
        username = get_req_header(conn, "x-username") |> List.first() || "API User"

        # Play the sound using the filename from the database
        SoundboardWeb.AudioPlayer.play_sound(sound.filename, username)

        json(conn, %{
          status: "success",
          message: "Playing sound: #{sound.filename}",
          played_by: username
        })
    end
  end

  def stop(conn, _params) do
    SoundboardWeb.AudioPlayer.stop_sound()

    json(conn, %{
      status: "success",
      message: "Stopped all sounds"
    })
  end

  defp format_sound(sound) do
    %{
      id: sound.id,
      filename: sound.filename,
      description: sound.description,
      tags: Enum.map(sound.tags, & &1.name),
      inserted_at: sound.inserted_at,
      updated_at: sound.updated_at
    }
  end
end
