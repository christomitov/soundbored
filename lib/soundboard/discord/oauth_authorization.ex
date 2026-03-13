defmodule Soundboard.Discord.OAuthAuthorization do
  @moduledoc """
  Evaluate whether an OAuth-authenticated Discord user is allowed into the app.
  """

  @env_guild_var "SOUNDBOARD_REQUIRED_GUILD_ID"
  @env_roles_var "SOUNDBOARD_ALLOWED_ROLE_IDS"

  @type auth :: map()
  @type authorize_result ::
          {:ok, :authorized}
          | {:ok, :authorized, [String.t()]}
          | {:error, atom()}

  @doc """
  Authorize an OAuth response.
  """
  @spec authorize(auth(), opts :: keyword()) ::
          {:ok, :authorized} | {:error, atom()}
  def authorize(auth, opts \\ [])

  def authorize(%{} = auth, opts) when is_list(opts) do
    include_roles = Keyword.get(opts, :return_roles, false)

    case authorize_with_roles(auth, opts) do
      {:ok, :authorized, roles} when include_roles ->
        {:ok, :authorized, roles}

      {:ok, :authorized, _roles} ->
        {:ok, :authorized}

      other ->
        other
    end
  end

  def authorize(_auth, _opts), do: {:error, :invalid_auth_payload}

  def authorize_with_roles(%{} = auth, opts) when is_list(opts) do
    required_guild_id =
      Keyword.get(opts, :required_guild_id, Application.get_env(:soundboard, :oauth_required_guild_id))
      |> normalize_guild_id()

    required_roles =
      Keyword.get(opts, :required_role_ids, Application.get_env(:soundboard, :oauth_allowed_role_ids))
      |> normalize_role_ids()

    case required_guild_id do
      nil -> {:ok, :authorized}
      "" -> {:ok, :authorized}
      _guild_id ->
        with {:ok, user_id} <- extract_user_id(auth),
             {:ok, access_token} <- extract_access_token(auth),
             {:ok, user_role_ids} <- member_roles(user_id, access_token, required_guild_id),
             :ok <- verify_required_roles(user_role_ids, required_roles) do
          {:ok, :authorized, user_role_ids}
        end
    end
  end

  def authorize_with_roles(_auth, _opts), do: {:error, :invalid_auth_payload}

  @doc """
  Convert an authorization reason into a user-visible flash message.
  """
  @spec error_message(atom()) :: String.t()
  def error_message(:not_in_guild), do: "Access denied: not a member of the required Discord server."
  def error_message(:missing_role), do: "Access denied: you do not have a required role."
  def error_message(:invalid_auth_payload), do: "Access denied: invalid Discord session data."
  def error_message(:missing_access_token), do: "Access denied: Discord auth token is missing."
  def error_message(:invalid_guild_id), do: "Access denied: role restriction is not configured correctly."
  def error_message(:missing_value), do: "Access denied: missing Discord login data."
  def error_message(:discord_member_lookup_failed), do: "Access denied: unable to confirm Discord membership."
  def error_message(:invalid_member_payload), do: "Access denied: unable to confirm Discord membership."
  def error_message(_), do: "Access denied: not authorized."

  defp member_roles(_user_id, _access_token, nil), do: {:ok, []}
  defp member_roles(_user_id, _access_token, ""), do: {:ok, []}

  defp member_roles(user_id, access_token, guild_id) do
    client = Application.get_env(:soundboard, :discord_member_client, Soundboard.Discord.MemberClient)

    case client.get_member_roles(guild_id, user_id, access_token) do
      {:ok, roles} -> {:ok, roles}
      {:error, :not_in_guild} -> {:error, :not_in_guild}
      {:error, :invalid_token} -> {:error, :missing_access_token}
      _ -> {:error, :discord_member_lookup_failed}
    end
  end

  defp verify_required_roles(_user_roles, []), do: :ok

  defp verify_required_roles(user_roles, required_roles) do
    user_set = MapSet.new(user_roles)
    required_set = MapSet.new(required_roles)

    if MapSet.intersection(user_set, required_set) |> Enum.empty?() do
      {:error, :missing_role}
    else
      :ok
    end
  end

  defp extract_user_id(%{} = auth) do
    with {:ok, uid} <- fetch_nested_key(auth, [:uid]),
         {:ok, normalized_uid} <- normalize_id(uid) do
      {:ok, normalized_uid}
    end
  end

  defp extract_access_token(%{} = auth) do
    with {:ok, credentials} <- fetch_nested_key(auth, [:credentials]),
         {:ok, token} <- fetch_nested_key(credentials, [:token]),
         {:ok, normalized_token} <- normalize_token(token) do
      {:ok, normalized_token}
    end
  end

  defp fetch_nested_key(%{} = source, [key]) do
    atom_key = key
    string_key = to_string(key)

    case source[atom_key] || source[string_key] do
      nil -> {:error, :missing_value}
      value -> {:ok, value}
    end
  end

  defp fetch_nested_key(%{} = source, [parent | rest]) do
    parent_key = to_string(parent)

    case source[parent] || source[parent_key] do
      nil -> {:error, :missing_value}
      nested -> nested |> fetch_nested_key(rest)
    end
  end

  defp fetch_nested_key(_source, _path), do: {:error, :missing_value}

  defp normalize_id(id) when is_binary(id) do
    value = String.trim(id)

    if value == "" do
      {:error, :invalid_guild_id}
    else
      {:ok, value}
    end
  end

  defp normalize_id(id), do: normalize_id(to_string(id))

  defp normalize_token(token) when is_binary(token) do
    value = String.trim(token)

    if value == "" do
      {:error, :missing_access_token}
    else
      {:ok, value}
    end
  end

  defp normalize_token(_), do: {:error, :missing_access_token}

  defp normalize_guild_id(nil) do
    normalized = Application.get_env(:soundboard, :oauth_required_guild_id)
    normalize_guild_id(normalized)
  end

  defp normalize_guild_id(guild_id) when is_binary(guild_id) do
    case String.trim(guild_id) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_guild_id(guild_id) when is_integer(guild_id), do: Integer.to_string(guild_id)

  defp normalize_guild_id(_), do: normalize_guild_id(System.get_env(@env_guild_var))

  defp normalize_role_ids(nil) do
    System.get_env(@env_roles_var)
    |> normalize_role_ids()
  end

  defp normalize_role_ids(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_role_ids(value) when is_list(value) do
    value
    |> Enum.flat_map(fn
      item when is_binary(item) -> [String.trim(item)]
      item when is_integer(item) -> [Integer.to_string(item)]
      _ -> []
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_role_ids(_), do: normalize_role_ids(System.get_env(@env_roles_var))
end
