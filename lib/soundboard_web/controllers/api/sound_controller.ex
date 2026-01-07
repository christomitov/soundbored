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
        username =
          case conn.assigns[:current_user] do
            %Soundboard.Accounts.User{username: uname} -> uname
            _ -> get_req_header(conn, "x-username") |> List.first() || "API User"
          end

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

  @doc """
  Play audio piped directly as raw binary data.

  Usage:
    curl -X POST "https://api.elevenlabs.io/v1/text-to-speech/VOICE_ID" \
      -H "xi-api-key: KEY" -d '{"text": "Hello"}' | \
    curl -X POST "/api/sounds/play-stream" \
      -H "Authorization: Bearer ..." \
      -H "Content-Type: audio/mpeg" \
      --data-binary @-
  """
  def play_stream(conn, _params) do
    username =
      case conn.assigns[:current_user] do
        %Soundboard.Accounts.User{username: uname} -> uname
        _ -> get_req_header(conn, "x-username") |> List.first() || "API User"
      end

    volume =
      (conn.query_params["volume"] || get_req_header(conn, "x-volume") |> List.first() || "1.0")
      |> parse_float()

    content_type = get_req_header(conn, "content-type") |> List.first() || "audio/mpeg"
    ext = case content_type do
      "audio/mpeg" -> "mp3"
      "audio/mp3" -> "mp3"
      "audio/wav" -> "wav"
      "audio/ogg" -> "ogg"
      _ -> "mp3"
    end

    {:ok, audio_data, conn} = Plug.Conn.read_body(conn)

    if byte_size(audio_data) > 0 do
      filename = "stream_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}.#{ext}"
      temp_path = Path.join(System.tmp_dir!(), filename)
      File.write!(temp_path, audio_data)

      SoundboardWeb.AudioPlayer.play_url(temp_path, volume, username)

      Task.start(fn ->
        Process.sleep(30_000)
        File.rm(temp_path)
      end)

      json(conn, %{status: "success", message: "Playing streamed audio", played_by: username})
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "No audio data received"})
    end
  end

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 1.0
    end
  end
  defp parse_float(_), do: 1.0
end
