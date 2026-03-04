defmodule Soundboard.Sounds.Uploads do
  @moduledoc """
  Shared sound upload/create pipeline used by both LiveView and API flows.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias Soundboard.{Repo, Sound, Stats, Tag, UserSoundSetting, Volume}

  @allowed_extensions ~w(.mp3 .wav .ogg .m4a)

  def allowed_extensions, do: @allowed_extensions

  def create(attrs) when is_map(attrs) do
    with {:ok, params} <- normalize_params(attrs),
         {:ok, source} <- prepare_source(params) do
      persist_sound(params, source)
    end
  end

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
        source_type = normalize_source_type(get_param(attrs, :source_type))
        name = normalize_name(get_param(attrs, :name))

        if blank?(name) do
          {:error, add_error(change(%Sound{}), :filename, "can't be blank")}
        else
          {:ok,
           %{
             user: user,
             source_type: source_type,
             name: name,
             url: normalize_url(get_param(attrs, :url)),
             tags: normalize_tags(get_param(attrs, :tags, [])),
             volume:
               Volume.percent_to_decimal(
                 get_param(attrs, :volume),
                 normalize_default_volume(get_param(attrs, :default_volume_percent, 100))
               ),
             is_join_sound: to_boolean(get_param(attrs, :is_join_sound)),
             is_leave_sound: to_boolean(get_param(attrs, :is_leave_sound)),
             upload: normalize_upload(get_param(attrs, :upload))
           }}
        end

      error ->
        error
    end
  end

  defp fetch_user(attrs) do
    case get_param(attrs, :user) do
      %Soundboard.Accounts.User{} = user -> {:ok, user}
      _ -> {:error, add_error(change(%Sound{}), :user_id, "can't be blank")}
    end
  end

  defp normalize_default_volume(value), do: Volume.normalize_percent(value, 100)

  defp prepare_source(%{source_type: "url"} = params) do
    filename = params.name <> url_file_extension(params.url)

    {:ok,
     %{
       filename: filename,
       source_type: "url",
       url: params.url,
       copied_file_path: nil
     }}
  end

  defp prepare_source(%{source_type: "local"} = params) do
    with {:ok, upload} <- validate_local_upload(params.upload),
         {:ok, ext} <- validate_local_extension(upload.filename),
         filename <- params.name <> ext,
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

  defp prepare_source(_params) do
    {:error, add_error(change(%Sound{}), :source_type, "must be either 'local' or 'url'")}
  end

  defp validate_local_upload(nil),
    do: {:error, add_error(change(%Sound{}), :file, "Please select a file")}

  defp validate_local_upload(%{path: path, filename: filename}) when is_binary(path) do
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

  defp validate_local_upload(_),
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
    uploads_dir = uploads_dir()
    dest_path = Path.join(uploads_dir, filename)

    if filename_taken?(filename) or File.exists?(dest_path) do
      {:error, add_error(change(%Sound{}), :filename, "has already been taken")}
    else
      File.mkdir_p!(uploads_dir)

      case File.cp(src_path, dest_path) do
        :ok -> {:ok, dest_path}
        {:error, _reason} -> {:error, "Error saving file"}
      end
    end
  end

  defp persist_sound(params, source) do
    Repo.transaction(fn ->
      with {:ok, tags} <- resolve_tags(params.tags),
           {:ok, sound} <- insert_sound(params, source, tags),
           {:ok, _setting} <- upsert_user_setting(sound, params),
           sound <- Repo.preload(sound, [:tags, :user, :user_sound_settings]) do
        broadcast_updates()
        sound
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, sound} ->
        {:ok, sound}

      {:error, reason} ->
        maybe_cleanup_local_file(source.copied_file_path, params)
        {:error, reason}
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

  defp upsert_user_setting(sound, params) do
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

  defp resolve_tags(tags) when is_list(tags) do
    tags
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn tag, {:ok, acc} ->
      case resolve_tag(tag) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, resolved_tag} -> {:cont, {:ok, [resolved_tag | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, tag_list} -> {:ok, Enum.reverse(tag_list) |> Enum.uniq_by(& &1.id)}
      error -> error
    end
  end

  defp resolve_tags(_), do: {:ok, []}

  defp resolve_tag(%Tag{} = tag), do: {:ok, tag}

  defp resolve_tag(tag_name) when is_binary(tag_name) do
    normalized =
      tag_name
      |> String.trim()
      |> String.downcase()

    if normalized == "" do
      {:error, add_error(change(%Sound{}), :tags, "can't be blank")}
    else
      find_or_create_tag(normalized)
    end
  end

  defp resolve_tag(_), do: {:ok, nil}

  defp find_or_create_tag(name) do
    case Repo.get_by(Tag, name: name) do
      %Tag{} = tag -> {:ok, tag}
      nil -> insert_or_get_tag(name)
    end
  end

  defp insert_or_get_tag(name) do
    case %Tag{} |> Tag.changeset(%{name: name}) |> Repo.insert() do
      {:ok, tag} -> {:ok, tag}
      {:error, _} -> fetch_tag_after_insert_conflict(name)
    end
  end

  defp fetch_tag_after_insert_conflict(name) do
    case Repo.get_by(Tag, name: name) do
      %Tag{} = tag -> {:ok, tag}
      nil -> {:error, add_error(change(%Sound{}), :tags, "is invalid")}
    end
  end

  defp filename_taken?(filename) do
    from(s in Sound, where: s.filename == ^filename)
    |> Repo.exists?()
  end

  defp broadcast_updates do
    Phoenix.PubSub.broadcast(Soundboard.PubSub, "uploads", {:sound_uploaded})
    Stats.broadcast_stats_update()
  end

  defp maybe_cleanup_local_file(path, _params) when is_binary(path) do
    _ = File.rm(path)
    :ok
  end

  defp maybe_cleanup_local_file(_reason, _attrs), do: :ok

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

  defp normalize_source_type(source_type) when is_binary(source_type) do
    source_type
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_source_type(_), do: "local"

  defp normalize_name(name) when is_binary(name), do: String.trim(name)
  defp normalize_name(_), do: nil

  defp normalize_url(url) when is_binary(url), do: String.trim(url)
  defp normalize_url(_), do: nil

  defp to_boolean(value) when value in [true, "true", "1", 1, "on", "yes"], do: true
  defp to_boolean(_), do: false

  defp get_param(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp uploads_dir do
    Application.get_env(:soundboard, :uploads_dir, "priv/static/uploads")
  end

  defp blank?(value), do: value in [nil, ""]
end
