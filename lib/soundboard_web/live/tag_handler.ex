defmodule SoundboardWeb.Live.TagHandler do
  @moduledoc """
  Handles the adding and removing of tags from sounds.
  """
  alias Phoenix.PubSub
  alias Soundboard.Accounts.Tenants
  alias Soundboard.{Repo, Sound, Tag}
  import Phoenix.Component, only: [assign: 3]

  def add_tag(socket, tag_name, current_tags) do
    tenant_id = tenant_id_from_socket(socket)
    tag_name = String.downcase(tag_name)

    with {:ok} <- validate_tag_name(tag_name),
         {:ok, tag} <- find_or_create_tag(tag_name, tenant_id),
         {:ok} <- validate_unique_tag(tag, current_tags) do
      add_tag_to_sound_or_upload(socket, tag, current_tags)
    end
  end

  defp validate_tag_name(""), do: {:error, "Tag name cannot be empty"}
  defp validate_tag_name(_), do: {:ok}

  defp validate_unique_tag(tag, current_tags) do
    if Enum.any?(current_tags, &(&1.id == tag.id)) do
      {:error, "Tag already exists"}
    else
      {:ok}
    end
  end

  defp add_tag_to_sound_or_upload(socket, tag, current_tags) do
    if socket.assigns.current_sound do
      add_tag_to_sound(socket, tag, current_tags)
    else
      {:ok, assign(socket, :upload_tags, [tag | current_tags])}
    end
  end

  defp add_tag_to_sound(socket, tag, current_tags) do
    case update_sound_tags(socket.assigns.current_sound, [tag | current_tags]) do
      {:ok, updated_sound} ->
        broadcast_update()
        {:ok, assign(socket, :current_sound, Repo.preload(updated_sound, :tags))}

      {:error, _} ->
        {:error, "Failed to add tag"}
    end
  end

  def remove_tag(socket, tag_name) do
    sound = socket.assigns.current_sound

    case Sound.changeset(sound, %{
           tags: Enum.reject(sound.tags, &(&1.name == tag_name))
         })
         |> Repo.update() do
      {:ok, updated_sound} ->
        broadcast_update()
        {:ok, updated_sound}

      {:error, _} ->
        {:error, "Failed to remove tag"}
    end
  end

  def search_tags(socket, query) when is_map(socket) do
    search_tags(query, tenant_id_from_socket(socket))
  end

  def search_tags(query, tenant_id) do
    query = String.downcase(query)
    tenant_id = tenant_id || default_tenant_id()

    Tag
    |> Tag.search(query, tenant_id)
    |> Repo.all()
  end

  def all_tags(sounds) do
    sounds
    |> Enum.flat_map(& &1.tags)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
  end

  def count_sounds_with_tag(sounds, tag) do
    Enum.count(sounds, fn sound ->
      Enum.any?(sound.tags, &(&1.id == tag.id))
    end)
  end

  def tag_selected?(tag, selected_tags) do
    Enum.any?(selected_tags, &(&1.id == tag.id))
  end

  def update_sound_tags(sound, tags) do
    sound
    |> Repo.preload(:tags)
    |> Sound.changeset(%{tags: tags})
    |> Repo.update()
  end

  def find_or_create_tag(name, tenant_id \\ default_tenant_id()) do
    name = String.downcase(name)

    case Repo.get_by(Tag, name: name, tenant_id: tenant_id) do
      nil ->
        %Tag{}
        |> Tag.changeset(%{name: name, tenant_id: tenant_id})
        |> Repo.insert()

      tag ->
        {:ok, tag}
    end
  end

  defp broadcast_update do
    PubSub.broadcast(Soundboard.PubSub, "soundboard", {:files_updated})
  end

  def list_tags_for_sound(filename, tenant_id \\ default_tenant_id()) do
    case Repo.get_by(Sound, filename: filename, tenant_id: tenant_id) do
      nil ->
        []

      sound ->
        sound
        |> Repo.preload(:tags)
        |> Map.get(:tags)
    end
  end

  defp tenant_id_from_socket(socket) do
    cond do
      tenant = socket.assigns[:current_tenant] ->
        tenant.id

      user = socket.assigns[:current_user] ->
        user.tenant_id

      true ->
        default_tenant_id()
    end
  end

  defp default_tenant_id do
    Tenants.ensure_default_tenant!().id
  end
end
