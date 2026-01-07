defmodule Soundboard.Repo do
  @adapter Application.compile_env(:soundboard, :repo_adapter, Ecto.Adapters.SQLite3)

  use Ecto.Repo,
    otp_app: :soundboard,
    adapter: @adapter
end
