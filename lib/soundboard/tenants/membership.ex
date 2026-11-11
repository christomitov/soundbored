defmodule Soundboard.Tenants.Membership do
  @moduledoc """
  Who may use and who may manage a guild's soundboard.

  A user may use a guild's soundboard only while they are a member of that
  Discord guild. The deployment's default guild (`Tenants.default_guild_id/0`)
  is open to every signed-in user, so self-hosted installs keep working with
  no configuration (the role check already gates who signs in there).

  Membership is read from Discord through `EDA.Cache.fetch_member/2`: the
  gateway's member cache first, the REST API on a miss. When Discord cannot
  be reached the answer is no.
  """

  alias Soundboard.Tenants
  alias Soundboard.Tenants.Guild

  @boundary_exceptions Soundboard.Boundary.exceptions()

  @spec member?(String.t() | term(), String.t() | nil) :: boolean()
  def member?(guild_id, discord_id) do
    guild_id = to_string(guild_id)

    cond do
      guild_id == Tenants.default_guild_id() -> true
      is_binary(discord_id) -> match?({:ok, _member}, fetch_member(guild_id, discord_id))
      true -> false
    end
  end

  @doc """
  Whether the user may manage the guild (claim its slug, run its billing):
  only the owner recorded when it was provisioned. A guild with no recorded
  owner is manageable only when it is the default guild.
  """
  @spec owner?(String.t() | term(), String.t() | nil) :: boolean()
  def owner?(guild_id, discord_id) do
    case Tenants.get_guild(guild_id) do
      %Guild{owner_discord_id: owner} when is_binary(owner) and owner != "" ->
        owner == discord_id

      _ ->
        to_string(guild_id) == Tenants.default_guild_id()
    end
  end

  defp fetch_member(guild_id, discord_id) do
    EDA.Cache.fetch_member(guild_id, discord_id)
  rescue
    _ in @boundary_exceptions -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
