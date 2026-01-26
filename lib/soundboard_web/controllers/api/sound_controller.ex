defmodule SoundboardWeb.API.SoundController do
  use SoundboardWeb, :controller

  import Ecto.Query
  alias Soundboard.Accounts.Tenants
  alias Soundboard.{Repo, Sound}

  def index(conn, _params) do
    tenant = current_tenant(conn)

    sounds =
      Sound
      |> where([s], s.tenant_id == ^tenant.id)
      |> Sound.with_tags()
      |> Repo.all()
      |> Enum.map(&format_sound/1)

    json(conn, %{data: sounds})
  end

  def play(conn, %{"id" => id}) do
    tenant = current_tenant(conn)

    case Repo.get_by(Sound, id: normalize_id(id), tenant_id: tenant.id) do
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
    tenant = current_tenant(conn)

    SoundboardWeb.AudioPlayer.stop_sound(tenant.id)

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
    username = stream_username(conn)
    volume = stream_volume(conn)
    ext = stream_extension(conn)

    {:ok, audio_data, conn} = Plug.Conn.read_body(conn)

    if byte_size(audio_data) > 0 do
      temp_path = write_stream_temp(audio_data, ext)

      SoundboardWeb.AudioPlayer.play_url(temp_path, volume, username)

      schedule_stream_cleanup(temp_path)

      json(conn, %{status: "success", message: "Playing streamed audio", played_by: username})
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "No audio data received"})
    end
  end

  defp current_tenant(conn) do
    conn.assigns[:current_tenant] || Tenants.ensure_default_tenant!()
  end

  defp normalize_id(id) when is_integer(id), do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, _} -> int
      :error -> -1
    end
  end

  defp normalize_id(_), do: -1

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 1.0
    end
  end

  defp parse_float(_), do: 1.0

  defp stream_username(conn) do
    case conn.assigns[:current_user] do
      %Soundboard.Accounts.User{username: uname} -> uname
      _ -> get_req_header(conn, "x-username") |> List.first() || "API User"
    end
  end

  defp stream_volume(conn) do
    (conn.query_params["volume"] || get_req_header(conn, "x-volume") |> List.first() || "1.0")
    |> parse_float()
  end

  defp stream_extension(conn) do
    case get_req_header(conn, "content-type") |> List.first() || "audio/mpeg" do
      "audio/mpeg" -> "mp3"
      "audio/mp3" -> "mp3"
      "audio/wav" -> "wav"
      "audio/ogg" -> "ogg"
      _ -> "mp3"
    end
  end

  defp write_stream_temp(audio_data, ext) do
    filename = "stream_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}.#{ext}"
    temp_path = Path.join(System.tmp_dir!(), filename)
    File.write!(temp_path, audio_data)
    temp_path
  end

  defp schedule_stream_cleanup(path) do
    Task.start(fn ->
      Process.sleep(30_000)
      File.rm(path)
    end)
  end
end
