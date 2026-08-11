defmodule Soundboard.YouTube.CookiesTest do
  use ExUnit.Case, async: false

  alias Soundboard.YouTube.Cookies

  setup do
    Cookies.clear()
    on_exit(fn -> Cookies.clear() end)
    :ok
  end

  @valid_netscape """
  # Netscape HTTP Cookie File
  .youtube.com	TRUE	/	FALSE	0	CONSENT	YES+
  .youtube.com	TRUE	/	TRUE	0	LOGIN_INFO	abc
  """

  test "validate_format accepts netscape youtube cookies" do
    assert :ok = Cookies.validate_format(@valid_netscape)
  end

  test "validate_format rejects empty content" do
    assert {:error, _} = Cookies.validate_format("   ")
  end

  test "validate_format rejects HTML" do
    assert {:error, message} = Cookies.validate_format("<!doctype html><html></html>")
    assert message =~ "HTML"
  end

  test "validate_format rejects cookies without youtube domain" do
    content = """
    .example.com	TRUE	/	FALSE	0	FOO	bar
    """

    assert {:error, message} = Cookies.validate_format(content)
    assert message =~ "youtube.com"
  end

  test "save persists validated cookies when ytdlp validate is skipped" do
    assert {:ok, status} = Cookies.save(@valid_netscape)
    assert status.present?
    assert is_binary(status.validated_at)
    assert File.regular?(Cookies.path())
  end

  test "clear removes cookies" do
    assert {:ok, _} = Cookies.save(@valid_netscape)
    assert Cookies.present?()
    assert :ok = Cookies.clear()
    refute Cookies.present?()
  end
end
