defmodule Soundboard.YouTube.YtDlpTest do
  use ExUnit.Case, async: false

  alias Soundboard.YouTube.YtDlp

  setup do
    previous_exe = Application.get_env(:soundboard, :ytdlp_executable)
    previous_managed = Application.get_env(:soundboard, :ytdlp_managed_path)
    previous_auto = Application.get_env(:soundboard, :ytdlp_auto_download)
    :persistent_term.erase({Soundboard.YouTube.YtDlp, :executable})

    on_exit(fn ->
      restore(:ytdlp_executable, previous_exe)
      restore(:ytdlp_managed_path, previous_managed)
      restore(:ytdlp_auto_download, previous_auto)
      :persistent_term.erase({Soundboard.YouTube.YtDlp, :executable})
    end)

    :ok
  end

  test "managed_path/0 uses configured managed path" do
    Application.put_env(:soundboard, :ytdlp_executable, :system)
    Application.put_env(:soundboard, :ytdlp_managed_path, "/tmp/soundboard-test-yt-dlp")

    assert YtDlp.managed_path() == "/tmp/soundboard-test-yt-dlp"
  end

  test "managed_path/0 prefers explicit YTDLP path as download destination" do
    Application.put_env(:soundboard, :ytdlp_executable, "/opt/custom/yt-dlp")
    assert YtDlp.managed_path() == "/opt/custom/yt-dlp"
  end

  test "ensure/0 remembers an existing managed binary path" do
    dir = Path.join(System.tmp_dir!(), "yt-dlp-test-#{System.unique_integer([:positive])}")
    path = Path.join(dir, "yt-dlp")
    File.mkdir_p!(dir)
    File.write!(path, "#!/bin/sh\necho ok\n")
    File.chmod!(path, 0o755)

    Application.put_env(:soundboard, :ytdlp_executable, :system)
    Application.put_env(:soundboard, :ytdlp_managed_path, path)
    Application.put_env(:soundboard, :ytdlp_auto_download, false)

    assert {:ok, ^path} = YtDlp.ensure()
    assert YtDlp.executable() == path
    assert Application.get_env(:soundboard, :ytdlp_executable) == path
  after
    # cleaned via tmp paths
    :ok
  end

  test "ensure/0 errors when disabled" do
    Application.put_env(:soundboard, :ytdlp_executable, false)
    assert {:error, message} = YtDlp.ensure()
    assert message =~ "disabled"
    assert YtDlp.executable() == nil
  end

  defp restore(key, nil), do: Application.delete_env(:soundboard, key)
  defp restore(key, value), do: Application.put_env(:soundboard, key, value)
end
