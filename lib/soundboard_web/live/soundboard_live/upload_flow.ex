defmodule SoundboardWeb.Live.SoundboardLive.UploadFlow do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Soundboard.Sound
  alias Soundboard.Sounds.Uploads
  alias Soundboard.Volume
  alias SoundboardWeb.Live.TagHandler

  @default_assigns %{
    show_upload_modal: false,
    source_type: "local",
    upload_name: "",
    url: "",
    upload_tags: [],
    upload_tag_input: "",
    upload_tag_suggestions: [],
    is_join_sound: false,
    is_leave_sound: false,
    upload_error: nil,
    upload_volume: 100
  }

  def assign_defaults(socket), do: assign_many(socket, @default_assigns)

  def change_source_type(socket, source_type) do
    {:noreply, assign(socket, :source_type, source_type)}
  end

  def save(socket, params, consume_uploaded_entries_fn) do
    case socket.assigns.source_type do
      "url" ->
        case Uploads.create(build_request(socket, params)) do
          {:ok, _sound} ->
            {:noreply,
             socket
             |> close_modal()
             |> assign(:uploaded_files, Sound.list_detailed())
             |> Phoenix.LiveView.put_flash(:info, "Sound added successfully")}

          {:error, reason} ->
            {:noreply, Phoenix.LiveView.put_flash(socket, :error, Uploads.error_message(reason))}
        end

      _ ->
        results =
          consume_uploaded_entries_fn.(socket, :audio, fn meta, entry ->
            request =
              socket
              |> build_request(params)
              |> Uploads.put_upload(%{path: meta.path, filename: entry.client_name})

            {:ok, Uploads.create(request)}
          end)

        handle_save_results(socket, results)
    end
  end

  def validate(socket, params) do
    socket = validate_existing_entries(socket)
    params = normalize_params(socket, params)

    case validate_request(socket, params) do
      :ok ->
        {:noreply, assign_params(socket, params, nil)}

      {:error, changeset} ->
        {:noreply, assign_params(socket, params, Uploads.error_message(changeset))}
    end
  end

  def show_modal(socket) do
    {:noreply,
     socket
     |> reset_state()
     |> assign(:show_upload_modal, true)}
  end

  def hide_modal(socket), do: {:noreply, close_modal(socket)}

  def close_modal(socket) do
    socket
    |> reset_state()
    |> assign(:show_upload_modal, false)
  end

  def add_tag(socket, key, value) do
    if key == "Enter" and value != "" do
      socket
      |> TagHandler.add_tag(value, socket.assigns.upload_tags)
      |> handle_tag_response(socket)
    else
      suggestions = TagHandler.search_tags(value)

      {:noreply,
       socket
       |> assign(:upload_tag_input, value)
       |> assign(:upload_tag_suggestions, suggestions)}
    end
  end

  def remove_tag(socket, tag_name) do
    upload_tags = Enum.reject(socket.assigns.upload_tags, &(&1.name == tag_name))
    {:noreply, assign(socket, :upload_tags, upload_tags)}
  end

  def select_tag_suggestion(socket, tag_name) do
    socket
    |> TagHandler.add_tag(tag_name, socket.assigns.upload_tags)
    |> handle_tag_response(socket)
  end

  def update_tag_input(socket, value) do
    suggestions = TagHandler.search_tags(value)

    {:noreply,
     socket
     |> assign(:upload_tag_input, value)
     |> assign(:upload_tag_suggestions, suggestions)}
  end

  def select_tag(socket, tag_name) do
    tag = Enum.find(TagHandler.search_tags(""), &(&1.name == tag_name))

    if tag do
      socket
      |> TagHandler.add_tag(tag_name, socket.assigns.upload_tags)
      |> handle_tag_response(socket)
    else
      {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Tag not found")}
    end
  end

  def toggle_join_sound(socket) do
    {:noreply, assign(socket, :is_join_sound, !socket.assigns.is_join_sound)}
  end

  def toggle_leave_sound(socket) do
    {:noreply, assign(socket, :is_leave_sound, !socket.assigns.is_leave_sound)}
  end

  def update_volume(socket, volume) do
    {:noreply,
     assign(
       socket,
       :upload_volume,
       Volume.normalize_percent(volume, socket.assigns.upload_volume)
     )}
  end

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
    |> assign(:upload_tag_input, "")
    |> assign(:upload_tag_suggestions, [])
  end

  defp reset_state(socket) do
    socket
    |> assign_many(Map.delete(@default_assigns, :show_upload_modal))
  end

  defp normalize_params(socket, params) do
    params
    |> Map.put_new("source_type", socket.assigns.source_type)
    |> Map.put_new("name", socket.assigns.upload_name)
    |> Map.put_new("url", socket.assigns.url)
  end

  defp assign_params(socket, params, error) do
    socket
    |> assign(:upload_error, error)
    |> assign(:upload_name, params["name"] || socket.assigns.upload_name)
    |> assign(:url, params["url"] || socket.assigns.url)
    |> assign(:source_type, params["source_type"] || socket.assigns.source_type)
  end

  defp validate_existing_entries(socket) do
    if socket.assigns.uploads.audio.entries == [] do
      socket
    else
      validate_audio_entries(socket)
    end
  end

  defp validate_audio_entries(socket) do
    case socket.assigns.uploads.audio.entries do
      [entry | _] ->
        case validate_audio(entry) do
          {:ok, _} -> socket
          {:error, error} -> Phoenix.LiveView.put_flash(socket, :error, error)
        end

      _ ->
        socket
    end
  end

  defp validate_audio(entry) do
    case entry.client_type do
      type when type in ~w(audio/mpeg audio/wav audio/ogg audio/x-m4a) -> {:ok, entry}
      _ -> {:error, "Invalid file type"}
    end
  end

  defp validate_request(socket, %{"source_type" => "url", "name" => name, "url" => url}) do
    if blank?(name) and blank?(url) do
      :ok
    else
      case Uploads.validate(build_request(socket, %{"name" => name, "url" => url})) do
        {:ok, _params} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp validate_request(socket, params) do
    request =
      socket
      |> build_request(params)
      |> Uploads.put_upload(current_upload(socket))

    case Uploads.validate(request) do
      {:ok, _params} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp handle_save_results(socket, [{:ok, {:ok, _sound}}]) do
    {:noreply,
     socket
     |> close_modal()
     |> assign(:uploaded_files, Sound.list_detailed())
     |> Phoenix.LiveView.put_flash(:info, "Sound added successfully")}
  end

  defp handle_save_results(socket, [{:ok, {:error, reason}}]) do
    {:noreply, Phoenix.LiveView.put_flash(socket, :error, Uploads.error_message(reason))}
  end

  defp handle_save_results(socket, []) do
    {:noreply,
     Phoenix.LiveView.put_flash(
       socket,
       :error,
       Uploads.error_message(
         %Ecto.Changeset{}
         |> Ecto.Changeset.change()
         |> Ecto.Changeset.add_error(:file, "Please select a file")
       )
     )}
  end

  defp handle_save_results(socket, _results) do
    {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Error saving file")}
  end

  defp build_request(socket, params) do
    Uploads.build_live_view_request(params, socket.assigns.current_user, %{
      source_type: socket.assigns.source_type,
      tags: socket.assigns.upload_tags,
      default_volume_percent: socket.assigns[:upload_volume] || 100,
      is_join_sound: socket.assigns.is_join_sound,
      is_leave_sound: socket.assigns.is_leave_sound
    })
  end

  defp current_upload(socket) do
    case Phoenix.LiveView.uploaded_entries(socket, :audio) do
      {[entry | _], _} -> %{filename: entry.client_name}
      {_, [entry | _]} -> %{filename: entry.client_name}
      _ -> nil
    end
  end

  defp blank?(value), do: value in [nil, ""]

  defp assign_many(socket, attrs) do
    Enum.reduce(attrs, socket, fn {key, value}, acc -> assign(acc, key, value) end)
  end
end
