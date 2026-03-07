defmodule SoundboardWeb.Live.SoundboardLive.EditFlow do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Soundboard.{Sound, Sounds, Volume}
  alias SoundboardWeb.Live.{LiveTags, TagForm}

  @tag_form %{input_key: :tag_input, suggestions_key: :tag_suggestions}

  defmodule State do
    @moduledoc false

    defstruct show_modal: false,
              current_sound: nil,
              tag_input: "",
              tag_suggestions: [],
              show_delete_confirm: false,
              edit_name_error: nil,
              current_user_id: nil

    @type t :: %__MODULE__{
            show_modal: boolean(),
            current_sound: Sound.t() | nil,
            tag_input: String.t(),
            tag_suggestions: list(),
            show_delete_confirm: boolean(),
            edit_name_error: String.t() | nil,
            current_user_id: integer() | nil
          }
  end

  def assign_defaults(socket), do: put_state(socket, default_state())

  def validate_sound(socket, %{"_target" => ["filename"]} = params) do
    current_sound_id = params["sound_id"]

    error =
      case Sounds.fetch_filename_extension(current_sound_id) do
        {:ok, extension} ->
          filename = String.trim(params["filename"] || "") <> extension

          if Sounds.filename_taken_excluding?(filename, current_sound_id) do
            "A sound with that name already exists"
          end

        :error ->
          nil
      end

    {:noreply, update_state(socket, &%{&1 | edit_name_error: error})}
  end

  def validate_sound(socket, _params), do: {:noreply, socket}

  def open_modal(socket, id) do
    sound = Sounds.get_sound!(id)

    {:noreply,
     socket
     |> update_state(fn state ->
       %{state | current_sound: sound, show_modal: true, edit_name_error: nil}
     end)}
  end

  def close_modal(socket), do: put_state(socket, default_state())

  def add_tag(socket, key, value) do
    edit = state(socket)

    TagForm.handle_key(socket, key, value, current_tags(edit), &append_sound_tag/3, @tag_form)
  end

  def remove_tag(socket, tag_name) do
    edit = state(socket)
    tags = Enum.reject(current_tags(edit), &(&1.name == tag_name))

    {:ok, updated_sound} = LiveTags.update_sound_tags(edit.current_sound, tags)
    LiveTags.broadcast_update()

    {:noreply,
     socket
     |> update_state(&%{&1 | current_sound: updated_sound})
     |> assign(:uploaded_files, Sounds.list_detailed())}
  end

  def select_tag_suggestion(socket, tag_name), do: select_tag(socket, tag_name)

  def update_tag_input(socket, value), do: TagForm.update_input(socket, value, @tag_form)

  def select_tag(socket, tag_name) do
    edit = state(socket)

    TagForm.select_tag(socket, tag_name, current_tags(edit), &append_sound_tag/3, @tag_form)
  end

  def save_sound(socket, params) do
    edit = state(socket)

    case Sounds.update_sound(edit.current_sound, edit.current_user_id, params) do
      {:ok, _updated_sound} ->
        LiveTags.broadcast_update()

        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(:info, "Sound updated successfully")
         |> close_modal()
         |> assign(:uploaded_files, Sounds.list_detailed())}

      {:error, error} ->
        {:noreply,
         Phoenix.LiveView.put_flash(
           socket,
           :error,
           "Error updating sound: #{error_message(error)}"
         )}
    end
  end

  def show_delete_confirm(socket) do
    {:noreply, update_state(socket, &%{&1 | show_delete_confirm: true})}
  end

  def hide_delete_confirm(socket) do
    {:noreply, update_state(socket, &%{&1 | show_delete_confirm: false})}
  end

  def delete_sound(socket) do
    edit = state(socket)

    case Sounds.delete_sound(edit.current_sound, edit.current_user_id) do
      :ok ->
        {:noreply,
         socket
         |> close_modal()
         |> assign(:uploaded_files, Sounds.list_detailed())
         |> Phoenix.LiveView.put_flash(:info, "Sound deleted successfully")}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> update_state(&%{&1 | show_delete_confirm: false})
         |> Phoenix.LiveView.put_flash(:error, "You can only delete your own sounds")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> update_state(&%{&1 | show_delete_confirm: false})
         |> Phoenix.LiveView.put_flash(:error, "Failed to delete sound")}
    end
  end

  def update_volume(socket, volume) do
    edit = state(socket)

    case edit.current_sound do
      nil ->
        {:noreply, socket}

      sound ->
        default_percent = Volume.decimal_to_percent(sound.volume)

        updated_sound =
          Map.put(sound, :volume, Volume.percent_to_decimal(volume, default_percent))

        {:noreply, update_state(socket, &%{&1 | current_sound: updated_sound})}
    end
  end

  defp error_message(%Ecto.Changeset{} = changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {msg, _opts}} ->
      "#{field} #{msg}"
    end)
  end

  defp error_message(_), do: "Failed to update sound"

  defp append_sound_tag(socket, tag, current_tags) do
    edit = state(socket)

    case LiveTags.update_sound_tags(edit.current_sound, [tag | current_tags]) do
      {:ok, updated_sound} ->
        LiveTags.broadcast_update()
        {:ok, update_state(socket, &%{&1 | current_sound: updated_sound})}

      {:error, _} ->
        {:error, "Failed to add tag"}
    end
  end

  defp current_tags(%State{current_sound: %{tags: tags}}) when is_list(tags), do: tags
  defp current_tags(_state), do: []

  defp default_state, do: %State{}

  defp state(socket) do
    %State{
      show_modal: Map.get(socket.assigns, :show_modal, false),
      current_sound: Map.get(socket.assigns, :current_sound),
      tag_input: Map.get(socket.assigns, :tag_input, ""),
      tag_suggestions: Map.get(socket.assigns, :tag_suggestions, []),
      show_delete_confirm: Map.get(socket.assigns, :show_delete_confirm, false),
      edit_name_error: Map.get(socket.assigns, :edit_name_error),
      current_user_id: socket.assigns[:current_user] && socket.assigns.current_user.id
    }
  end

  defp update_state(socket, fun) when is_function(fun, 1) do
    socket
    |> state()
    |> fun.()
    |> then(&put_state(socket, &1))
  end

  defp put_state(socket, %State{} = state) do
    socket
    |> assign(:edit_state, state)
    |> assign(:show_modal, state.show_modal)
    |> assign(:current_sound, state.current_sound)
    |> assign(:tag_input, state.tag_input)
    |> assign(:tag_suggestions, state.tag_suggestions)
    |> assign(:show_delete_confirm, state.show_delete_confirm)
    |> assign(:edit_name_error, state.edit_name_error)
  end
end
