defmodule Soundboard.RuntimeConfigTest do
  # Regression test for issue #79: the URL the bot advertises (join message,
  # OAuth callback) must not carry the internal bind port. Phoenix falls back
  # to the listener port when url[:port] is nil, so the runtime config must
  # publish the explicit scheme default (443/80), which renders without a
  # port suffix.
  use ExUnit.Case, async: false

  @env %{
    "DISCORD_TOKEN" => "test-token",
    "DISCORD_CLIENT_ID" => "test-id",
    "DISCORD_CLIENT_SECRET" => "test-secret",
    "PHX_HOST" => "soundboard.example",
    "SCHEME" => "https",
    "PORT" => "4000",
    "SECRET_KEY_BASE" => String.duplicate("a", 96)
  }

  setup do
    original = Map.new(@env, fn {key, _} -> {key, System.get_env(key)} end)

    System.put_env(@env)

    on_exit(fn ->
      Enum.each(original, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)
  end

  test "the advertised URL uses the scheme default port, never the bind port" do
    for env <- [:dev, :prod] do
      config = Config.Reader.read!("config/runtime.exs", env: env, imports: [])
      url = config[:soundboard][SoundboardWeb.Endpoint][:url]

      assert url[:scheme] == "https"
      assert url[:host] == "soundboard.example"
      assert url[:port] == 443
    end
  end

  test "a nonstandard public port can be published through PHX_HOST" do
    System.put_env("PHX_HOST", "soundboard.example:8443")

    for env <- [:dev, :prod] do
      config = Config.Reader.read!("config/runtime.exs", env: env, imports: [])
      url = config[:soundboard][SoundboardWeb.Endpoint][:url]

      assert url[:host] == "soundboard.example:8443"
    end
  end
end
