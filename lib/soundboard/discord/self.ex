defmodule Soundboard.Discord.Self do
  @moduledoc false

  alias EDA.API.User
  alias EDA.Cache

  def get do
    case Cache.me() do
      nil -> fetch_self()
      user -> {:ok, normalize_user(user)}
    end
  end

  defp fetch_self do
    case User.me() do
      {:ok, user} ->
        Cache.put_me(user)
        {:ok, normalize_user(user)}

      other ->
        other
    end
  end

  defp normalize_user(%{id: id}), do: %{id: id}
  defp normalize_user(%{"id" => id}), do: %{id: id}
  defp normalize_user(_), do: %{}
end
