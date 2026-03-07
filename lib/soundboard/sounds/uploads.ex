defmodule Soundboard.Sounds.Uploads do
  @moduledoc """
  Shared sound upload/create pipeline used by both LiveView and API flows.
  """

  defmodule CreateRequest do
    @moduledoc false

    alias Soundboard.Accounts.User

    @enforce_keys [:user, :source_type, :name]
    defstruct [
      :user,
      :source_type,
      :name,
      :url,
      :upload,
      :tags,
      :volume,
      :is_join_sound,
      :is_leave_sound,
      :default_volume_percent
    ]

    @type upload ::
            %Plug.Upload{}
            | %{
                optional(:path) => String.t(),
                optional(:filename) => String.t(),
                optional(:client_name) => String.t(),
                optional(String.t()) => String.t()
              }

    @type t :: %__MODULE__{
            user: User.t(),
            source_type: String.t(),
            name: String.t(),
            url: String.t() | nil,
            upload: upload() | nil,
            tags: [map() | String.t()] | nil,
            volume: String.t() | number() | nil,
            is_join_sound: boolean() | String.t() | nil,
            is_leave_sound: boolean() | String.t() | nil,
            default_volume_percent: String.t() | number() | nil
          }
  end

  import Ecto.Changeset
  import Ecto.Query

  alias Soundboard.{PubSubTopics, Repo, Sound, Stats, UploadsPath, UserSoundSetting, Volume}
  alias Soundboard.Sounds.Tags

  @type upload_attrs :: %{
          optional(:path) => String.t(),
          optional(:filename) => String.t(),
          optional(String.t()) => String.t()
        }

  @type live_view_options :: %{
          required(:source_type) => String.t(),
          required(:tags) => list(),
          required(:default_volume_percent) => number(),
          required(:is_join_sound) => boolean(),
          required(:is_leave_sound) => boolean()
        }

  @type create_attrs :: map() | CreateRequest.t()
  @type create_error :: Ecto.Changeset.t()
  @type create_result :: {:ok, struct()} | {:error, create_error()}

  @allowed_extensions ~w(.mp3 .wav .ogg .m4a)

  @spec allowed_extensions() :: [String.t()]
  def allowed_extensions, do: @allowed_extensions

  @spec build_create_request(map(), Soundboard.Accounts.User.t(), map()) :: CreateRequest.t()
  def build_create_request(raw_params, user, overrides \\ %{}) when is_map(raw_params) do
    source_type = infer_request_source_type(raw_params)

    %CreateRequest{
      user: user,
      source_type: source_type,
      name: get_param(raw_params, :name),
      url: get_param(raw_params, :url),
      upload: get_param(raw_params, :upload) || get_param(raw_params, :file),
      tags: get_param(raw_params, :tags) || get_param(raw_params, "tags[]") || [],
      volume: get_param(raw_params, :volume),
      is_join_sound: get_param(raw_params, :is_join_sound),
      is_leave_sound: get_param(raw_params, :is_leave_sound),
      default_volume_percent: get_param(raw_params, :default_volume_percent)
    }
    |> merge_request_overrides(overrides)
  end

  @spec build_api_request(map(), Soundboard.Accounts.User.t()) :: CreateRequest.t()
  def build_api_request(raw_params, user), do: build_create_request(raw_params, user)

  @spec build_live_view_request(map(), Soundboard.Accounts.User.t(), live_view_options()) ::
          CreateRequest.t()
  def build_live_view_request(raw_params, user, options) do
    build_create_request(raw_params, user, %{
      tags: Map.fetch!(options, :tags),
      default_volume_percent: Map.fetch!(options, :default_volume_percent),
      is_join_sound: Map.fetch!(options, :is_join_sound),
      is_leave_sound: Map.fetch!(options, :is_leave_sound),
      source_type: Map.fetch!(options, :source_type)
    })
  end

  @spec put_upload(CreateRequest.t(), upload_attrs() | nil) :: CreateRequest.t()
  def put_upload(%CreateRequest{} = request, upload) do
    struct!(request, upload: normalize_upload(upload))
  end

  @spec validate(create_attrs()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def validate(%CreateRequest{} = request) do
    with {:ok, params} <- normalize_request(request),
         {:ok, _source} <- prepare_source(params, :validate) do
      {:ok, params}
    end
  end

  def validate(attrs) when is_map(attrs) do
    with {:ok, params} <- normalize_params(attrs),
         {:ok, _source} <- prepare_source(params, :validate) do
      {:ok, params}
    end
  end

  @spec create(create_attrs()) :: create_result()
  def create(%CreateRequest{} = request) do
    with {:ok, params} <- normalize_request(request),
         {:ok, source} <- prepare_source(params, :create) do
      persist_sound(params, source)
    else
      {:error, reason} -> {:error, normalize_create_error(reason)}
    end
  end

  def create(attrs) when is_map(attrs) do
    with {:ok, params} <- normalize_params(attrs),
         {:ok, source} <- prepare_source(params, :create) do
      persist_sound(params, source)
    else
      {:error, reason} -> {:error, normalize_create_error(reason)}
    end
  end

  @spec error_message(Ecto.Changeset.t() | String.t() | term()) :: String.t()
  def error_message(%Ecto.Changeset{} = changeset) do
    Enum.map_join(changeset.errors, ", ", fn
      {:filename, {"has already been taken", _}} -> "A sound with that name already exists"
      {:file, {"Please select a file", _}} -> "Please select a file"
      {key, {msg, _}} -> "#{key} #{msg}"
    end)
  end

  def error_message(error) when is_binary(error), do: error
  def error_message(_), do: "An unexpected error occurred"

  @spec url_file_extension(String.t() | term()) :: String.t()
  def url_file_extension(url) when is_binary(url) do
    ext =
      url
      |> URI.parse()
      |> Map.get(:path)
      |> case do
        nil -> ""
        path -> String.downcase(Path.extname(path || ""))
      end

    if ext in @allowed_extensions, do: ext, else: ""
  end

  def url_file_extension(_), do: ""

  defp normalize_params(attrs) do
    case fetch_user(attrs) do
      {:ok, user} ->
        upload = normalize_upload(get_param(attrs, :upload))
        url = normalize_url(get_param(attrs, :url))
        source_type = normalize_source_type(get_param(attrs, :source_type), upload, url)
        name = normalize_name(get_param(attrs, :name))

        build_normalized_params(%{
          user: user,
          source_type: source_type,
          name: name,
          url: url,
          tags: get_param(attrs, :tags, []),
          volume: get_param(attrs, :volume),
          is_join_sound: get_param(attrs, :is_join_sound),
          is_leave_sound: get_param(attrs, :is_leave_sound),
          default_volume_percent: get_param(attrs, :default_volume_percent, 100),
          upload: upload
        })

      error ->
        error
    end
  end

  defp normalize_request(%CreateRequest{} = request) do
    upload = normalize_upload(request.upload)
    url = normalize_url(request.url)
    source_type = normalize_source_type(request.source_type, upload, url)
    name = normalize_name(request.name)

    build_normalized_params(%{
      user: request.user,
      source_type: source_type,
      name: name,
      url: url,
      tags: request.tags,
      volume: request.volume,
      is_join_sound: request.is_join_sound,
      is_leave_sound: request.is_leave_sound,
      default_volume_percent: request.default_volume_percent || 100,
      upload: upload
    })
  end

  defp fetch_user(attrs) do
    case get_param(attrs, :user) do
      %Soundboard.Accounts.User{} = user -> {:ok, user}
      _ -> {:error, add_error(change(%Sound{}), :user_id, "can't be blank")}
    end
  end

  defp build_normalized_params(%{
         user: %Soundboard.Accounts.User{} = user,
         source_type: source_type,
         name: name,
         url: url,
         tags: tags,
         volume: volume,
         is_join_sound: is_join_sound,
         is_leave_sound: is_leave_sound,
         default_volume_percent: default_volume_percent,
         upload: upload
       }) do
    if blank?(name) do
      {:error, add_error(change(%Sound{}), :filename, "can't be blank")}
    else
      {:ok,
       %{
         user: user,
         source_type: source_type,
         name: name,
         url: url,
         tags: normalize_tags(tags),
         volume:
           Volume.percent_to_decimal(volume, normalize_default_volume(default_volume_percent)),
         is_join_sound: to_boolean(is_join_sound),
         is_leave_sound: to_boolean(is_leave_sound),
         upload: upload
       }}
    end
  end

  defp build_normalized_params(_params) do
    {:error, add_error(change(%Sound{}), :user_id, "can't be blank")}
  end

  defp normalize_default_volume(value), do: Volume.normalize_percent(value, 100)

  defp prepare_source(%{source_type: "url"} = params, _mode) do
    with {:ok, url} <- validate_url(params.url),
         filename <- params.name <> url_file_extension(url),
         :ok <- validate_destination_filename(filename) do
      {:ok,
       %{
         filename: filename,
         source_type: "url",
         url: url,
         copied_file_path: nil
       }}
    end
  end

  defp prepare_source(%{source_type: "local"} = params, :validate) do
    with {:ok, upload} <- validate_local_upload(params.upload, :validate),
         {:ok, ext} <- validate_local_extension(upload.filename),
         filename <- params.name <> ext,
         :ok <- validate_destination_filename(filename) do
      {:ok,
       %{
         filename: filename,
         source_type: "local",
         url: nil,
         copied_file_path: nil
       }}
    end
  end

  defp prepare_source(%{source_type: "local"} = params, :create) do
    with {:ok, upload} <- validate_local_upload(params.upload, :create),
         {:ok, ext} <- validate_local_extension(upload.filename),
         filename <- params.name <> ext,
         :ok <- validate_destination_filename(filename),
         {:ok, copied_file_path} <- copy_local_file(upload.path, filename) do
      {:ok,
       %{
         filename: filename,
         source_type: "local",
         url: nil,
         copied_file_path: copied_file_path
       }}
    end
  end

  defp prepare_source(_params, _mode) do
    {:error, add_error(change(%Sound{}), :source_type, "must be either 'local' or 'url'")}
  end

  defp validate_url(url) when is_binary(url) do
    if blank?(url) do
      {:error, add_error(change(%Sound{}), :url, "can't be blank")}
    else
      {:ok, url}
    end
  end

  defp validate_url(_url), do: {:error, add_error(change(%Sound{}), :url, "can't be blank")}

  defp validate_local_upload(nil, _mode),
    do: {:error, add_error(change(%Sound{}), :file, "Please select a file")}

  defp validate_local_upload(%{filename: filename} = upload, :validate) do
    if blank?(filename) do
      {:error, add_error(change(%Sound{}), :file, "Please select a file")}
    else
      {:ok, %{path: Map.get(upload, :path), filename: filename}}
    end
  end

  defp validate_local_upload(%{path: path, filename: filename}, :create) when is_binary(path) do
    if blank?(filename) do
      {:error,
       add_error(
         change(%Sound{}),
         :file,
         "Invalid file upload"
       )}
    else
      {:ok, %{path: path, filename: filename}}
    end
  end

  defp validate_local_upload(_, _mode),
    do: {:error, add_error(change(%Sound{}), :file, "Please select a file")}

  defp validate_local_extension(filename) do
    ext = filename |> Path.extname() |> String.downcase()

    if ext in @allowed_extensions do
      {:ok, ext}
    else
      {:error,
       add_error(
         change(%Sound{}),
         :file,
         "Invalid file type. Please upload an MP3, WAV, OGG, or M4A file."
       )}
    end
  end

  defp copy_local_file(src_path, filename) do
    uploads_dir = UploadsPath.dir()
    dest_path = UploadsPath.file_path(filename)

    with :ok <- ensure_uploads_dir(uploads_dir),
         :ok <- File.cp(src_path, dest_path) do
      {:ok, dest_path}
    else
      {:error, _reason} ->
        {:error, add_error(change(%Sound{}), :file, "Error saving file")}
    end
  end

  defp ensure_uploads_dir(uploads_dir) do
    case File.mkdir_p(uploads_dir) do
      :ok -> :ok
      {:error, _reason} -> {:error, add_error(change(%Sound{}), :file, "Error saving file")}
    end
  end

  defp persist_sound(params, source) do
    Repo.transaction(fn ->
      with {:ok, tags} <- resolve_tags(params.tags),
           {:ok, sound} <- insert_sound(params, source, tags),
           {:ok, _setting} <- insert_user_setting(sound, params),
           sound <- Repo.preload(sound, [:tags, :user, :user_sound_settings]) do
        sound
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, sound} ->
        broadcast_updates()
        {:ok, sound}

      {:error, reason} ->
        maybe_cleanup_local_file(source.copied_file_path, params)
        {:error, normalize_create_error(reason)}
    end
  end

  defp insert_sound(params, source, tags) do
    sound_attrs = %{
      filename: source.filename,
      source_type: source.source_type,
      url: source.url,
      user_id: params.user.id,
      volume: params.volume,
      tags: tags
    }

    %Sound{}
    |> Sound.changeset(sound_attrs)
    |> Repo.insert()
  end

  defp insert_user_setting(sound, params) do
    attrs = %{
      user_id: params.user.id,
      sound_id: sound.id,
      is_join_sound: params.is_join_sound,
      is_leave_sound: params.is_leave_sound
    }

    %UserSoundSetting{}
    |> UserSoundSetting.changeset(attrs)
    |> Repo.insert()
  end

  defp resolve_tags(tags), do: Tags.resolve_many(tags)

  defp validate_destination_filename(filename) do
    dest_path = UploadsPath.file_path(filename)

    if filename_taken?(filename) or File.exists?(dest_path) do
      {:error, add_error(change(%Sound{}), :filename, "has already been taken")}
    else
      :ok
    end
  end

  defp filename_taken?(filename) do
    from(s in Sound, where: s.filename == ^filename)
    |> Repo.exists?()
  end

  defp broadcast_updates do
    PubSubTopics.broadcast_files_updated()
    Stats.broadcast_stats_update()
  end

  defp maybe_cleanup_local_file(path, _params) when is_binary(path) do
    _ = File.rm(path)
    :ok
  end

  defp maybe_cleanup_local_file(_reason, _attrs), do: :ok

  defp normalize_create_error(%Ecto.Changeset{} = changeset), do: changeset
  defp normalize_create_error(message) when is_binary(message), do: add_base_error(message)
  defp normalize_create_error(_reason), do: add_base_error("An unexpected error occurred")

  defp add_base_error(message) do
    change(%Sound{})
    |> add_error(:base, message)
  end

  defp normalize_tags(nil), do: []

  defp normalize_tags(tags) when is_binary(tags) do
    tags
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_tags(tags) when is_list(tags), do: tags
  defp normalize_tags(_), do: []

  defp normalize_upload(nil), do: nil

  defp normalize_upload(upload) when is_map(upload) do
    %{
      path: get_param(upload, :path),
      filename: get_param(upload, :filename) || get_param(upload, :client_name)
    }
  end

  defp normalize_upload(_), do: nil

  defp normalize_source_type(source_type, upload, url) when is_binary(source_type) do
    case source_type |> String.trim() |> String.downcase() do
      "local" -> "local"
      "url" -> "url"
      _ -> infer_source_type(upload, url)
    end
  end

  defp normalize_source_type(_source_type, upload, url), do: infer_source_type(upload, url)

  defp infer_source_type(upload, url) do
    cond do
      is_map(upload) -> "local"
      is_binary(url) and String.trim(url) != "" -> "url"
      true -> "local"
    end
  end

  defp normalize_name(name) when is_binary(name), do: String.trim(name)
  defp normalize_name(_), do: nil

  defp normalize_url(url) when is_binary(url), do: String.trim(url)
  defp normalize_url(_), do: nil

  defp to_boolean(value) when value in [true, "true", "1", 1, "on", "yes"], do: true
  defp to_boolean(_), do: false

  defp merge_request_overrides(%CreateRequest{} = request, overrides) when is_map(overrides) do
    overrides
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case request_field(key) do
        nil -> acc
        field -> Map.put(acc, field, value)
      end
    end)
    |> then(&struct!(request, &1))
  end

  defp request_field(key)
       when is_atom(key) and
              key in [
                :user,
                :source_type,
                :name,
                :url,
                :upload,
                :tags,
                :volume,
                :is_join_sound,
                :is_leave_sound,
                :default_volume_percent
              ],
       do: key

  defp request_field(key) when is_binary(key) do
    key
    |> String.to_existing_atom()
    |> request_field()
  rescue
    ArgumentError -> nil
  end

  defp request_field(_key), do: nil

  defp infer_request_source_type(raw_params) do
    source_type = get_param(raw_params, :source_type)
    upload = get_param(raw_params, :upload) || get_param(raw_params, :file)
    url = get_param(raw_params, :url)

    normalize_source_type(source_type, upload, url)
  end

  defp get_param(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp blank?(value), do: value in [nil, ""]
end
