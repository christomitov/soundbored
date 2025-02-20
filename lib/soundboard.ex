defmodule Soundboard do
  @moduledoc """
  Soundboard keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  Returns the application name.
  """
  def app_name, do: :soundboard
end
