defmodule SoundboardWeb.Live.Support.SoundPlayback do
  @moduledoc false

  import Phoenix.LiveView, only: [put_flash: 3]

  alias Soundboard.Discord.RolePermissions
  alias Soundboard.Accounts.User

  def play(socket, sound_name) do
    case socket.assigns[:current_user] do
      %User{username: username} = user ->
        case RolePermissions.authorize_play(user) do
          :ok ->
            Soundboard.AudioPlayer.play_sound(sound_name, username)
            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, RolePermissions.permission_message(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "You must be logged in to play sounds")}
    end
  end

  def current_username(socket) do
    case socket.assigns[:current_user] do
      %User{username: username} -> {:ok, username}
      _ -> :error
    end
  end
end
