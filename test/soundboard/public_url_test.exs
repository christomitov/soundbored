defmodule Soundboard.PublicURLTest do
  use ExUnit.Case, async: false

  alias Soundboard.PublicURL

  test "from_uri_or_current/1 keeps the request host and strips only default ports" do
    assert PublicURL.from_uri_or_current("https://soundboard.example:443/settings") ==
             "https://soundboard.example"

    assert PublicURL.from_uri_or_current("http://localhost:80/settings") ==
             "http://localhost"

    assert PublicURL.from_uri_or_current("http://localhost:4000/settings") ==
             "http://localhost:4000"
  end

  test "from_uri_or_current/1 falls back to the configured public URL for invalid input" do
    assert PublicURL.from_uri_or_current(nil) == SoundboardWeb.Endpoint.url()
    assert PublicURL.from_uri_or_current("not a uri") == SoundboardWeb.Endpoint.url()
  end
end
