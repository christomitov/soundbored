ExUnit.start()

# Ensure the application is started
Application.ensure_all_started(:soundboard)

# Set the default sandbox mode
Ecto.Adapters.SQL.Sandbox.mode(Soundboard.Repo, :manual)
