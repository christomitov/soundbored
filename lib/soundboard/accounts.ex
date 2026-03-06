defmodule Soundboard.Accounts do
  @moduledoc """
  Accounts boundary helpers used by web and runtime code.
  """

  alias Soundboard.Accounts.User
  alias Soundboard.Repo

  def get_user(user_id), do: Repo.get(User, user_id)
end
