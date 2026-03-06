defmodule Soundboard.Accounts do
  @moduledoc """
  Accounts boundary helpers used by web and runtime code.
  """

  alias Soundboard.Accounts.User
  alias Soundboard.Repo
  import Ecto.Query

  def get_user(user_id), do: Repo.get(User, user_id)

  def avatars_by_usernames([]), do: %{}

  def avatars_by_usernames(usernames) when is_list(usernames) do
    from(u in User, where: u.username in ^usernames, select: {u.username, u.avatar})
    |> Repo.all()
    |> Map.new()
  end
end
