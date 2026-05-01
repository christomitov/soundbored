defmodule Soundboard.Discord.RoleChecker do
  @moduledoc false
  require Logger

  alias EDA.API.Member

  @doc """
  Check if the role-gated access feature is enabled.

  Returns true only when both required_guild_id and required_role_ids are configured.
  """
  def feature_enabled? do
    guild_id = Application.get_env(:soundboard, :required_guild_id)
    role_ids = Application.get_env(:soundboard, :required_role_ids, [])

    not is_nil(guild_id) and Enum.any?(role_ids)
  end

  @doc """
  Check if a user is authorized to access the application.

  Returns true if:
  - The feature is disabled, OR
  - The user's member object contains at least one of the required roles

  Returns false if:
  - The feature is enabled and the API call fails, OR
  - The user has none of the required roles, OR
  - The API response shape is unexpected
  """
  def authorized?(user_id) do
    if feature_enabled?() do
      check_member_roles(user_id)
    else
      true
    end
  end

  defp check_member_roles(user_id) do
    guild_id = Application.get_env(:soundboard, :required_guild_id)

    guild_id
    |> Member.get(user_id)
    |> member_authorized?(user_id)
  end

  defp member_authorized?({:ok, %{"roles" => roles}}, user_id) when is_list(roles) do
    required_role_ids = Application.get_env(:soundboard, :required_role_ids, [])
    authorized = Enum.any?(roles, &Enum.member?(required_role_ids, &1))

    unless authorized do
      Logger.info("Discord user #{user_id} has no matching required roles")
    end

    authorized
  end

  defp member_authorized?({:ok, _member}, user_id) do
    Logger.warning("Unexpected member response shape for Discord user #{user_id}")
    false
  end

  defp member_authorized?({:error, reason}, user_id) do
    Logger.error("Member API error for Discord user #{user_id}: #{inspect(reason)}")
    false
  end
end
