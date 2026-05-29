ExUnit.start()

Application.ensure_all_started(:soundboard)

Ecto.Adapters.SQL.Sandbox.mode(Soundboard.Repo, :manual)
