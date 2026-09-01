defmodule Soundboard.Tenants do
  @moduledoc """
  Multi-tenant context.

  A tenant is a Discord guild with a provisioned soundboard: a row in the
  `guilds` table plus a slug that maps to `{slug}.soundbored.app`.

  Backward compatibility: every guild-scoped operation falls back to
  `default_guild_id/0` when no guild is given, so existing single-guild
  deployments behave identically with zero configuration.
  """

  import Ecto.Query

  alias Soundboard.{Repo, Sound, Tenants.Guild}
  @boundary_exceptions Soundboard.Boundary.exceptions()

  @fallback_guild_id "default"
  @fallback_storage_bytes 2_147_483_648
  @reserved_slugs ~w(www dash api admin app auth uploads static assets mail settings stats favorites)

  # -- Guild resolution -------------------------------------------------------

  @doc """
  The guild used when no tenant is specified.

  Resolution order: `SOUNDBOARD_DEFAULT_GUILD_ID` env (configured as
  `:default_guild_id`), the existing `DISCORD_REQUIRED_GUILD_ID` env
  (configured as `:required_guild_id`), then the literal `"default"`.
  """
  @spec default_guild_id() :: String.t()
  def default_guild_id do
    Application.get_env(:soundboard, :default_guild_id) ||
      Application.get_env(:soundboard, :required_guild_id) ||
      @fallback_guild_id
  end

  @doc "The guild id to scope by: the given id, or the default guild."
  @spec scope_guild_id(String.t() | nil) :: String.t()
  def scope_guild_id(nil), do: default_guild_id()
  def scope_guild_id(guild_id) when is_binary(guild_id), do: guild_id

  @doc """
  Lists the guilds the shared Discord bot is a member of, with their tenant
  rows (if claimed). Used by the guild switcher and onboarding.
  """
  @spec bot_guilds() :: [%{id: String.t(), name: String.t() | nil, guild: Guild.t() | nil}]
  def bot_guilds do
    guilds =
      try do
        Soundboard.Discord.GuildCache.all()
      rescue
        _ in @boundary_exceptions ->
          []
      catch
        :exit, _ -> []
      end

    tenant_rows = Map.new(list_guilds(), &{&1.discord_guild_id, &1})

    Enum.map(guilds, fn g ->
      id = to_string(g.id)

      %{id: id, name: map_field(g, :name), guild: Map.get(tenant_rows, id)}
    end)
  end

  defp map_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  # -- Guild CRUD -------------------------------------------------------------

  @spec list_guilds() :: [Guild.t()]
  def list_guilds, do: Repo.all(Guild)

  @spec get_guild(String.t() | term()) :: Guild.t() | nil
  def get_guild(discord_guild_id),
    do: Repo.get_by(Guild, discord_guild_id: to_string(discord_guild_id))

  @spec get_by_slug(String.t()) :: Guild.t() | nil
  def get_by_slug(slug), do: Repo.get_by(Guild, slug: slug)

  @spec get_or_create_guild(String.t() | term(), map()) :: {:ok, Guild.t()} | {:error, term()}
  def get_or_create_guild(discord_guild_id, attrs \\ %{}) do
    case get_guild(discord_guild_id) do
      %Guild{} = guild ->
        {:ok, guild}

      nil ->
        discord_guild_id = to_string(discord_guild_id)

        # ponytail: provisional slug "guild-<id>" — unique by construction;
        # claim_slug/2 renames it when someone claims a real subdomain
        attrs = Map.put_new(attrs, :slug, "guild-#{discord_guild_id}")

        %Guild{}
        |> Guild.changeset(Map.merge(%{discord_guild_id: discord_guild_id}, attrs))
        |> Repo.insert()
    end
  end

  @doc """
  Claims `{slug}` for the given Discord guild, creating the tenant row if
  needed. Returns `{:error, :slug_taken}` / `{:error, :invalid_slug}` /
  `{:error, changeset}`.
  """
  @spec claim_slug(String.t() | term(), String.t()) ::
          {:ok, Guild.t()} | {:error, :slug_taken | :invalid_slug | Ecto.Changeset.t()}
  def claim_slug(discord_guild_id, slug) do
    with {:ok, slug} <- normalize_slug(slug),
         :ok <- ensure_slug_available(slug, discord_guild_id) do
      case get_guild(discord_guild_id) do
        %Guild{} = guild ->
          guild
          |> Guild.changeset(%{slug: slug})
          |> Repo.update()

        nil ->
          %Guild{}
          |> Guild.changeset(%{discord_guild_id: to_string(discord_guild_id), slug: slug})
          |> Repo.insert()
      end
    end
  end

  @doc "Whether a slug can be claimed (valid format, not reserved, not taken)."
  @spec slug_available?(String.t()) :: boolean()
  def slug_available?(slug) do
    case normalize_slug(slug) do
      {:ok, slug} ->
        get_by_slug(slug) == nil and slug not in @reserved_slugs

      {:error, :invalid_slug} ->
        false
    end
  end

  def reserved_slugs, do: @reserved_slugs

  defp normalize_slug(slug) when is_binary(slug) do
    slug = slug |> String.trim() |> String.downcase()

    if Regex.match?(~r/^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$/, slug) and
         slug not in @reserved_slugs do
      {:ok, slug}
    else
      {:error, :invalid_slug}
    end
  end

  defp normalize_slug(_), do: {:error, :invalid_slug}

  defp ensure_slug_available(slug, discord_guild_id) do
    case get_by_slug(slug) do
      nil ->
        :ok

      %Guild{discord_guild_id: id} ->
        if id == to_string(discord_guild_id), do: :ok, else: {:error, :slug_taken}
    end
  end

  @doc """
  Changeset helper: defaults a blank `guild_id` to the default guild, so
  pre-tenant call sites and single-guild deployments keep working unchanged.
  """
  @spec put_default_guild_id(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def put_default_guild_id(changeset) do
    case Ecto.Changeset.get_field(changeset, :guild_id) do
      v when v in [nil, ""] ->
        Ecto.Changeset.put_change(changeset, :guild_id, default_guild_id())

      _ ->
        changeset
    end
  end

  # -- Storage caps -----------------------------------------------------------

  @doc """
  Bytes of uploaded storage used by a guild. Sounds with unknown size
  (`byte_size = 0`, e.g. rows created before guild scoping) count as zero, so
  existing deployments are never retroactively blocked by a cap.
  """
  @spec storage_used(String.t() | term()) :: non_neg_integer()
  def storage_used(guild_id) do
    guild_id = scope_guild_id(guild_id)

    from(s in Sound,
      where: s.guild_id == ^guild_id,
      select: coalesce(sum(s.byte_size), 0)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  The storage cap for a guild: its own `max_storage_bytes`, else
  `SOUNDBOARD_DEFAULT_STORAGE_BYTES` (configured as `:default_storage_bytes`),
  else the built-in 2GB fallback.
  """
  @spec storage_cap(String.t() | term()) :: pos_integer()
  def storage_cap(guild_id) do
    case get_guild(guild_id) do
      %Guild{max_storage_bytes: bytes} when is_integer(bytes) and bytes > 0 -> bytes
      _ -> default_storage_bytes()
    end
  end

  @spec default_storage_bytes() :: pos_integer()
  def default_storage_bytes do
    Application.get_env(:soundboard, :default_storage_bytes) || @fallback_storage_bytes
  end

  @spec storage_remaining(String.t() | term()) :: non_neg_integer()
  def storage_remaining(guild_id) do
    max(storage_cap(guild_id) - storage_used(guild_id), 0)
  end

  @doc """
  Whether uploading `incoming_bytes` more would stay within the guild's cap.
  """
  @spec within_storage_limit?(String.t() | term(), non_neg_integer()) :: boolean()
  def within_storage_limit?(guild_id, incoming_bytes) do
    storage_used(guild_id) + incoming_bytes <= storage_cap(guild_id)
  end
end
