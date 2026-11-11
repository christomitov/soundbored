ExUnit.start()

System.delete_env("AUTO_JOIN")
System.delete_env("VOICE_IDLE_TIMEOUT_SECONDS")
{:ok, _} = Soundboard.FakeVoice.start()

Application.ensure_all_started(:soundboard)

Ecto.Adapters.SQL.Sandbox.mode(Soundboard.Repo, :manual)
