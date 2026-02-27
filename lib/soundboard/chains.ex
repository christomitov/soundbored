defmodule Soundboard.Chains do
  @moduledoc """
  Context for user sound chains.
  """
  import Ecto.Query

  alias Soundboard.Chains.{Chain, ChainItem}
  alias Soundboard.{Repo, Sound}

  def list_user_chains(nil), do: []

  def list_user_chains(user_id) do
    Chain
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.inserted_at)
    |> preload_chain_associations()
    |> Repo.all()
  end

  def list_public_chains(exclude_user_id \\ nil) do
    Chain
    |> where([c], c.is_public == true)
    |> maybe_exclude_user(exclude_user_id)
    |> order_by([c], desc: c.inserted_at)
    |> preload_chain_associations()
    |> Repo.all()
  end

  def get_playable_chain(user_id, chain_id) do
    chain_id = normalize_id(chain_id)

    query =
      from c in Chain,
        where: c.id == ^chain_id and (c.user_id == ^user_id or c.is_public == true)

    case query |> preload_chain_associations() |> Repo.one() do
      nil -> {:error, :not_found}
      chain -> {:ok, chain}
    end
  end

  def create_chain(user_id, attrs) do
    attrs = normalize_attrs(attrs)
    sound_ids = Map.get(attrs, :sound_ids, [])
    chain_attrs = attrs |> Map.drop([:sound_ids]) |> Map.put(:user_id, user_id)

    Repo.transaction(fn ->
      chain =
        case %Chain{} |> Chain.changeset(chain_attrs) |> Repo.insert() do
          {:ok, chain} -> chain
          {:error, changeset} -> Repo.rollback(changeset)
        end

      parsed_sound_ids = Enum.map(sound_ids, &normalize_id/1)

      if parsed_sound_ids == [] do
        Repo.rollback(:empty_chain)
      end

      existing_ids = existing_sound_ids(parsed_sound_ids)

      if Enum.any?(parsed_sound_ids, &(not MapSet.member?(existing_ids, &1))) do
        Repo.rollback(:invalid_sound)
      end

      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      entries =
        parsed_sound_ids
        |> Enum.with_index()
        |> Enum.map(fn {sound_id, position} ->
          %{
            chain_id: chain.id,
            sound_id: sound_id,
            position: position,
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} = Repo.insert_all(ChainItem, entries)

      if count != length(entries) do
        Repo.rollback(:insert_failed)
      end

      chain |> Repo.preload([:user, chain_items: chain_items_query()])
    end)
    |> normalize_create_result()
  end

  def delete_chain(user_id, chain_id) do
    chain_id = normalize_id(chain_id)

    case Repo.get_by(Chain, id: chain_id, user_id: user_id) do
      nil -> {:error, :not_found}
      chain -> Repo.delete(chain)
    end
  end

  defp normalize_create_result({:ok, chain}), do: {:ok, chain}
  defp normalize_create_result({:error, :empty_chain}), do: {:error, :empty_chain}
  defp normalize_create_result({:error, :invalid_sound}), do: {:error, :invalid_sound}
  defp normalize_create_result({:error, changeset}), do: {:error, changeset}

  defp maybe_exclude_user(query, nil), do: query
  defp maybe_exclude_user(query, user_id), do: where(query, [c], c.user_id != ^user_id)

  defp preload_chain_associations(query) do
    from c in query,
      preload: [:user, chain_items: ^chain_items_query()]
  end

  defp chain_items_query do
    from ci in ChainItem,
      order_by: [asc: ci.position],
      preload: [:sound]
  end

  defp existing_sound_ids(sound_ids) do
    Sound
    |> where([s], s.id in ^sound_ids)
    |> select([s], s.id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    name = Map.get(attrs, :name) || Map.get(attrs, "name")

    %{
      name: if(is_binary(name), do: String.trim(name), else: name),
      is_public: Map.get(attrs, :is_public) || Map.get(attrs, "is_public") || false,
      sound_ids: Map.get(attrs, :sound_ids) || Map.get(attrs, "sound_ids") || []
    }
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
