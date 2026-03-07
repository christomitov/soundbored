defmodule SoundboardWeb.Live.SoundboardLive.EditFlow do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Soundboard.{Favorites, Sound, Volume}
  alias Soundboard.Sounds.Management
  alias SoundboardWeb.Live.TagHandler

  @pubsub_topic "soundboard"
  @default_assigns %{
    show_modal: false,
    current_sound: nil,
    tag_input: "",
    tag_suggestions: [],
    show_delete_confirm: false,
    edit_name_error: nil
  }

  def assign_defaults(socket), do: assign_many(socket, @default_assigns)

  def validate_sound(socket, %{"_target" => ["filename"]} = params) do
    current_sound_id = params["sound_id"]

    case Sound.fetch_filename_extension(current_sound_id) do
      {:ok, extension} ->
        filename = String.trim(params["filename"] || "") <> extension

        if Sound.filename_taken_excluding?(filename, current_sound_id) do
          {:noreply, assign(socket, :edit_name_error, "A sound with that name already exists")}
        else
          {:noreply, assign(socket, :edit_name_error, nil)}
        end

      :error ->
        {:noreply, assign(socket, :edit_name_error, nil)}
    end
  end

  def validate_sound(socket, _params), do: {:noreply, socket}

  def open_modal(socket, id) do
    sound = Sound.get_sound!(id)

    {:noreply,
     socket
     |> assign(:current_sound, sound)
     |> assign(:show_modal, true)
     |> assign(:edit_name_error, nil)}
  end

  def close_modal(socket) do
    socket
    |> assign_many(@default_assigns)
  end

  def add_tag(socket, key, value) do
    if key == "Enter" and value != "" do
      socket
      |> TagHandler.add_tag(value, socket.assigns.current_sound.tags)
      |> handle_tag_response(socket)
    else
      suggestions = TagHandler.search_tags(value)

      {:noreply,
       socket
       |> assign(:tag_input, value)
       |> assign(:tag_suggestions, suggestions)}
    end
  end

  def remove_tag(socket, tag_name) do
    sound = socket.assigns.current_sound
    tags = Enum.reject(sound.tags, &(&1.name == tag_name))

    {:ok, updated_sound} = TagHandler.update_sound_tags(sound, tags)

    {:noreply,
     socket
     |> assign(:current_sound, updated_sound)
     |> assign(:uploaded_files, Sound.list_detailed())}
  end

  def select_tag_suggestion(socket, tag_name) do
    socket
    |> TagHandler.add_tag(tag_name, socket.assigns.current_sound.tags)
    |> handle_tag_response(socket)
  end

  def update_tag_input(socket, value) do
    suggestions = TagHandler.search_tags(value)

    {:noreply,
     socket
     |> assign(:tag_input, value)
     |> assign(:tag_suggestions, suggestions)}
  end

  def select_tag(socket, tag_name) do
    tag = Enum.find(TagHandler.search_tags(""), &(&1.name == tag_name))
    sound = socket.assigns.current_sound

    if tag do
      case TagHandler.update_sound_tags(sound, [tag | sound.tags]) do
        {:ok, updated_sound} ->
          {:noreply,
           socket
           |> assign(:current_sound, updated_sound)
           |> assign(:tag_input, "")
           |> assign(:tag_suggestions, [])
           |> assign(:uploaded_files, Sound.list_detailed())}

        {:error, _} ->
          {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Failed to add tag")}
      end
    else
      {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Tag not found")}
    end
  end

  def save_sound(socket, params) do
    sound = socket.assigns.current_sound
    user_id = socket.assigns.current_user.id

    case Management.update_sound(sound, user_id, params) do
      {:ok, _updated_sound} ->
        broadcast_update()

        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(:info, "Sound updated successfully")
         |> close_modal()
         |> assign(:uploaded_files, Sound.list_detailed())}

      {:error, error} ->
        {:noreply,
         Phoenix.LiveView.put_flash(
           socket,
           :error,
           "Error updating sound: #{error_message(error)}"
         )}
    end
  end

  def show_delete_confirm(socket), do: {:noreply, assign(socket, :show_delete_confirm, true)}

  def hide_delete_confirm(socket), do: {:noreply, assign(socket, :show_delete_confirm, false)}

  def delete_sound(socket) do
    sound = socket.assigns.current_sound
    user_id = socket.assigns.current_user.id

    case Management.delete_sound(sound, user_id) do
      :ok ->
        {:noreply,
         socket
         |> close_modal()
         |> assign(:uploaded_files, Sound.list_detailed())
         |> Phoenix.LiveView.put_flash(:info, "Sound deleted successfully")}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> assign(:show_delete_confirm, false)
         |> Phoenix.LiveView.put_flash(:error, "You can only delete your own sounds")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:show_delete_confirm, false)
         |> Phoenix.LiveView.put_flash(:error, "Failed to delete sound")}
    end
  end

  def update_volume(socket, volume) do
    case socket.assigns.current_sound do
      nil ->
        {:noreply, socket}

      sound ->
        default_percent = Volume.decimal_to_percent(sound.volume)

        updated_sound =
          Map.put(sound, :volume, Volume.percent_to_decimal(volume, default_percent))

        {:noreply, assign(socket, :current_sound, updated_sound)}
    end
  end

  def assign_favorites(socket, nil), do: assign(socket, :favorites, [])

  def assign_favorites(socket, user) do
    favorites = Favorites.list_favorites(user.id)
    assign(socket, :favorites, favorites)
  end

  defp error_message(%Ecto.Changeset{} = changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {msg, _opts}} ->
      "#{field} #{msg}"
    end)
  end

  defp error_message(_), do: "Failed to update sound"

  defp handle_tag_response({:ok, updated_socket}, _socket) do
    {:noreply, reset_tag_assigns(updated_socket)}
  end

  defp handle_tag_response({:error, message}, socket) do
    {:noreply,
     socket
     |> reset_tag_assigns()
     |> Phoenix.LiveView.put_flash(:error, message)}
  end

  defp reset_tag_assigns(socket) do
    socket
    |> assign(:tag_input, "")
    |> assign(:tag_suggestions, [])
  end

  defp broadcast_update do
    Phoenix.PubSub.broadcast(Soundboard.PubSub, @pubsub_topic, {:files_updated})
  end

  defp assign_many(socket, attrs) do
    Enum.reduce(attrs, socket, fn {key, value}, acc -> assign(acc, key, value) end)
  end
end
