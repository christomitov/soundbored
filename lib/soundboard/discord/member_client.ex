defmodule Soundboard.Discord.MemberClient do
  @moduledoc """
  Discord API client for pulling a user's guild membership info with an OAuth token.
  """

  @api_base "https://discord.com/api/v10"
  @request_timeout 5_000
  @user_agent "Soundbored OAuth Authorization"

  @spec get_member_roles(String.t(), String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, term()}
  def get_member_roles(guild_id, user_id, token)
      when is_binary(guild_id) and is_binary(user_id) and is_binary(token) do
    ensure_http_clients_started()

    case request_member(guild_id, user_id, token) do
      {:ok, body} ->
        decode_roles(body)

      {:error, _reason} = error ->
        error
    end
  end

  def get_member_roles(_guild_id, _user_id, _token) do
    {:error, :invalid_arguments}
  end

  defp request_member(guild_id, user_id, token) do
    headers = [
      {'Authorization', to_charlist("Bearer #{token}")},
      {'User-Agent', String.to_charlist(@user_agent)},
      {'Accept', 'application/json'}
    ]

    path = "/guilds/#{guild_id}/members/#{user_id}"
    url = @api_base <> path
    options = [timeout: @request_timeout]

    case :httpc.request(:get, {to_charlist(url), headers}, options, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, ensure_binary_body(body)}

      {:ok, {{_, 404, _}, _headers, _body}} ->
        {:error, :not_in_guild}

      {:ok, {{_, 401, _}, _headers, _body}} ->
        {:error, :invalid_token}

      {:ok, {{_, 403, _}, _headers, _body}} ->
        {:error, :insufficient_permissions}

      {:ok, {{_, status, _}, _headers, _body}} when is_integer(status) ->
        {:error, {:discord_http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_http_clients_started do
    case :inets.start() do
      :ok -> :ok
      {:error, {:already_started, :inets}} -> :ok
      _ -> :ok
    end

    case :ssl.start() do
      :ok -> :ok
      {:error, {:already_started, :ssl}} -> :ok
      _ -> :ok
    end
  end

  defp decode_roles(body) when is_binary(body) do
    with {:ok, decoded} <- Jason.decode(body),
         {:ok, roles} <- extract_roles(decoded) do
      {:ok, roles}
    else
      {:error, _reason} -> {:error, :invalid_discord_response}
    end
  end

  defp decode_roles(_), do: {:error, :invalid_discord_response}

  defp extract_roles(%{} = payload) do
    roles = payload["roles"] || payload[:roles]

    if is_list(roles) do
      {:ok, Enum.map(roles, &to_string/1)}
    else
      {:error, :invalid_member_payload}
    end
  end

  defp extract_roles(_), do: {:error, :invalid_member_payload}

  defp ensure_binary_body(body) when is_binary(body), do: body
  defp ensure_binary_body(body) when is_list(body), do: List.to_string(body)
  defp ensure_binary_body(_), do: ""
end
