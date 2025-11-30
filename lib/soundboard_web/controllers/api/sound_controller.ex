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
end
