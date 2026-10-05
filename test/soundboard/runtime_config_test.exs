defmodule Soundboard.RuntimeConfigTest do
  # Regression test for issue #79 in prod: the advertised URL must not carry
  # the internal bind port. Phoenix falls back to the listener port when
  # url[:port] is nil, so prod publishes the explicit scheme default (443/80).
  # Dev intentionally advertises the bind port: it talks straight to the
  # server, there is no reverse proxy in front of it.
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

  test "dev advertises the bind port, prod uses the scheme default" do
    dev = Config.Reader.read!("config/runtime.exs", env: :dev, imports: [])
    prod = Config.Reader.read!("config/runtime.exs", env: :prod, imports: [])

    dev_url = dev[:soundboard][SoundboardWeb.Endpoint][:url]
    prod_url = prod[:soundboard][SoundboardWeb.Endpoint][:url]

    assert dev_url[:port] == 4000
    assert prod_url[:port] == 443
    assert prod_url[:scheme] == "https"
    assert prod_url[:host] == "soundboard.example"
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
