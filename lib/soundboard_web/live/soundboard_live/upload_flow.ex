defmodule SoundboardWeb.Live.SoundboardLive.UploadFlow do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Soundboard.{Sounds, Volume}
  alias SoundboardWeb.Live.TagForm

  @tag_form %{input_key: :upload_tag_input, suggestions_key: :upload_tag_suggestions}

  defmodule State do
    @moduledoc false

    defstruct show_upload_modal: false,
              source_type: "local",
              upload_name: "",
              url: "",
              upload_tags: [],
              upload_tag_input: "",
              upload_tag_suggestions: [],
              is_join_sound: false,
              is_leave_sound: false,
              upload_error: nil,
              upload_volume: 100,
              current_user: nil,
              audio_entries: [],
              current_upload: nil

    @type t :: %__MODULE__{
            show_upload_modal: boolean(),
            source_type: String.t(),
            upload_name: String.t(),
            url: String.t(),
            upload_tags: list(),
            upload_tag_input: String.t(),
            upload_tag_suggestions: list(),
            is_join_sound: boolean(),
            is_leave_sound: boolean(),
            upload_error: String.t() | nil,
            upload_volume: number(),
            current_user: term(),
            audio_entries: list(),
            current_upload: map() | nil
          }
  end

  def assign_defaults(socket), do: put_state(socket, default_state())

  def change_source_type(socket, source_type) do
    {:noreply, update_state(socket, &%{&1 | source_type: source_type})}
  end

  def save(socket, params, consume_uploaded_entries_fn) do
    upload = state(socket)

    case upload.source_type do
      "url" ->
        case Sounds.create_sound(build_request(upload, params)) do
          {:ok, _sound} ->
            {:noreply,
             socket
             |> close_modal()
             |> assign(:uploaded_files, Sounds.list_detailed())
             |> Phoenix.LiveView.put_flash(:info, "Sound added successfully")}

          {:error, changeset} ->
            {:noreply,
             Phoenix.LiveView.put_flash(socket, :error, Sounds.create_error_message(changeset))}
        end

      _ ->
        results =
          consume_uploaded_entries_fn.(socket, :audio, fn meta, entry ->
            request =
              upload
              |> build_request(params)
              |> Sounds.put_request_upload(%{path: meta.path, filename: entry.client_name})

            {:ok, Sounds.create_sound(request)}
          end)

        handle_save_results(socket, results)
    end
  end

  def validate(socket, params) do
    upload = state(socket)
    socket = validate_existing_entries(socket, upload)
    upload = state(socket)
    params = normalize_params(upload, params)

    case validate_request(upload, params) do
      :ok ->
        {:noreply, assign_params(socket, upload, params, nil)}

      {:error, changeset} ->
        {:noreply, assign_params(socket, upload, params, Sounds.create_error_message(changeset))}
    end
  end

  def show_modal(socket) do
    {:noreply,
     socket
     |> reset_state()
     |> update_state(&%{&1 | show_upload_modal: true})}
  end

  def hide_modal(socket), do: {:noreply, close_modal(socket)}

  def close_modal(socket) do
    socket
    |> reset_state()
    |> update_state(&%{&1 | show_upload_modal: false})
  end

  def add_tag(socket, key, value) do
    upload = state(socket)

    TagForm.handle_key(socket, key, value, upload.upload_tags, &append_upload_tag/3, @tag_form)
  end

  def remove_tag(socket, tag_name) do
    {:noreply,
     update_state(socket, fn upload ->
       %{upload | upload_tags: Enum.reject(upload.upload_tags, &(&1.name == tag_name))}
     end)}
  end

  def select_tag_suggestion(socket, tag_name), do: select_tag(socket, tag_name)

  def update_tag_input(socket, value), do: TagForm.update_input(socket, value, @tag_form)

  def select_tag(socket, tag_name) do
    upload = state(socket)

    TagForm.select_tag(socket, tag_name, upload.upload_tags, &append_upload_tag/3, @tag_form)
  end

  def toggle_join_sound(socket) do
    {:noreply, update_state(socket, &%{&1 | is_join_sound: !&1.is_join_sound})}
  end

  def toggle_leave_sound(socket) do
    {:noreply, update_state(socket, &%{&1 | is_leave_sound: !&1.is_leave_sound})}
  end

  def update_volume(socket, volume) do
    {:noreply,
     update_state(socket, fn upload ->
       %{upload | upload_volume: Volume.normalize_percent(volume, upload.upload_volume)}
     end)}
  end

  defp append_upload_tag(socket, tag, current_tags) do
    {:ok, update_state(socket, &%{&1 | upload_tags: [tag | current_tags]})}
  end

  defp reset_state(socket), do: put_state(socket, default_state())

  defp normalize_params(upload, params) do
    params
    |> Map.put_new("source_type", upload.source_type)
    |> Map.put_new("name", default_upload_name(upload, params))
    |> Map.put_new("url", upload.url)
  end

  defp assign_params(socket, upload, params, error) do
    update_state(socket, fn state ->
      %{
        state
        | upload_error: error,
          upload_name: params["name"] || upload.upload_name,
          url: params["url"] || upload.url,
          source_type: params["source_type"] || upload.source_type
      }
    end)
  end

  defp validate_existing_entries(socket, %State{audio_entries: []}), do: socket

  defp validate_existing_entries(socket, %State{} = upload) do
    case upload.audio_entries do
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

  defp validate_request(upload, %{"source_type" => "url", "name" => name, "url" => url}) do
    if blank?(name) and blank?(url) do
      :ok
    else
      case Sounds.validate_create(build_request(upload, %{"name" => name, "url" => url})) do
        {:ok, _params} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp validate_request(upload, params) do
    request =
      upload
      |> build_request(params)
      |> Sounds.put_request_upload(upload.current_upload)

    case Sounds.validate_create(request) do
      {:ok, _params} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp handle_save_results(socket, [{:ok, _sound}]) do
    {:noreply,
     socket
     |> close_modal()
     |> assign(:uploaded_files, Sounds.list_detailed())
     |> Phoenix.LiveView.put_flash(:info, "Sound added successfully")}
  end

  defp handle_save_results(socket, [{:error, changeset}]) do
    {:noreply, Phoenix.LiveView.put_flash(socket, :error, Sounds.create_error_message(changeset))}
  end

  defp handle_save_results(socket, []) do
    {:noreply,
     Phoenix.LiveView.put_flash(
       socket,
       :error,
       Sounds.create_error_message(
         %Ecto.Changeset{}
         |> Ecto.Changeset.change()
         |> Ecto.Changeset.add_error(:file, "Please select a file")
       )
     )}
  end

  defp handle_save_results(socket, _results) do
    {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Error saving file")}
  end

  defp build_request(%State{} = upload, params) do
    Sounds.new_create_request(upload.current_user, %{
      source_type: upload.source_type,
      name: params["name"],
      url: params["url"],
      tags: upload.upload_tags,
      volume: params["volume"],
      default_volume_percent: upload.upload_volume,
      is_join_sound: upload.is_join_sound,
      is_leave_sound: upload.is_leave_sound
    })
  end

  defp default_upload_name(upload, params) do
    current_name = upload.upload_name
    source_type = params["source_type"] || upload.source_type
    url = params["url"] || upload.url

    cond do
      present?(current_name) -> current_name
      source_type == "local" -> inferred_upload_name(upload.current_upload)
      source_type == "url" -> inferred_url_name(url)
      true -> ""
    end
  end

  defp inferred_upload_name(%{filename: filename}) when is_binary(filename) do
    filename
    |> Path.basename()
    |> Path.rootname()
  end

  defp inferred_upload_name(_), do: ""

  defp inferred_url_name(url) when is_binary(url) do
    url
    |> URI.parse()
    |> Map.get(:path, "")
    |> Path.basename()
    |> Path.rootname()
    |> case do
      "." -> ""
      name -> name
    end
  end

  defp inferred_url_name(_), do: ""

  defp default_state, do: %State{}

  defp state(socket) do
    %State{
      show_upload_modal: Map.get(socket.assigns, :show_upload_modal, false),
      source_type: Map.get(socket.assigns, :source_type, "local"),
      upload_name: Map.get(socket.assigns, :upload_name, ""),
      url: Map.get(socket.assigns, :url, ""),
      upload_tags: Map.get(socket.assigns, :upload_tags, []),
      upload_tag_input: Map.get(socket.assigns, :upload_tag_input, ""),
      upload_tag_suggestions: Map.get(socket.assigns, :upload_tag_suggestions, []),
      is_join_sound: Map.get(socket.assigns, :is_join_sound, false),
      is_leave_sound: Map.get(socket.assigns, :is_leave_sound, false),
      upload_error: Map.get(socket.assigns, :upload_error),
      upload_volume: Map.get(socket.assigns, :upload_volume, 100),
      current_user: Map.get(socket.assigns, :current_user),
      audio_entries: audio_entries(socket),
      current_upload: current_upload(socket)
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
    |> assign(:upload_state, state)
    |> assign(:show_upload_modal, state.show_upload_modal)
    |> assign(:source_type, state.source_type)
    |> assign(:upload_name, state.upload_name)
    |> assign(:url, state.url)
    |> assign(:upload_tags, state.upload_tags)
    |> assign(:upload_tag_input, state.upload_tag_input)
    |> assign(:upload_tag_suggestions, state.upload_tag_suggestions)
    |> assign(:is_join_sound, state.is_join_sound)
    |> assign(:is_leave_sound, state.is_leave_sound)
    |> assign(:upload_error, state.upload_error)
    |> assign(:upload_volume, state.upload_volume)
  end

  defp audio_entries(socket) do
    socket.assigns
    |> Map.get(:uploads, %{})
    |> Map.get(:audio)
    |> case do
      %{entries: entries} when is_list(entries) -> entries
      _ -> []
    end
  end

  defp current_upload(socket) do
    if get_in(socket.assigns, [:uploads, :audio]) do
      case Phoenix.LiveView.uploaded_entries(socket, :audio) do
        {[entry | _], _} -> %{filename: entry.client_name}
        {_, [entry | _]} -> %{filename: entry.client_name}
        _ -> nil
      end
    else
      nil
    end
  end

  defp blank?(value), do: value in [nil, ""]
  defp present?(value), do: not blank?(value)
end
