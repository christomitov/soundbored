defmodule Soundboard.Repo do
  use Ecto.Repo,
    otp_app: :soundboard,
    adapter: Ecto.Adapters.SQLite3
end
