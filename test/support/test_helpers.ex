defmodule Soundboard.TestHelpers do
  alias Soundboard.{Repo, Sound, Tag}

  def create_test_file(filename) do
    test_dir = "test/support/fixtures"
    File.mkdir_p!(test_dir)
    path = Path.join(test_dir, filename)
    File.write!(path, "test audio content")
    path
  end

  def cleanup_test_files do
    File.rm_rf!("test/support/fixtures")
  end

  def setup_test_socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(
          %{
            current_user: nil,
            current_sound: nil,
            uploads: %{},
            flash: %{}
          },
          assigns
        )
    }
  end

  def setup_upload_socket(user) do
    setup_test_socket(%{
      current_user: user,
      uploads: %{
        audio: %Phoenix.LiveView.UploadConfig{
          entries: [],
          ref: "test-ref",
          max_entries: 1,
          max_file_size: 10_000_000,
          chunk_size: 64_000,
          chunk_timeout: 10_000,
          accept: ~w(.mp3 .wav .ogg .m4a)
        }
      }
    })
  end

  def setup_test_audio_file do
    test_dir = "test/support/fixtures"
    File.mkdir_p!(test_dir)
    file_path = Path.join(test_dir, "test_sound.mp3")
    File.write!(file_path, "test audio content")
    file_path
  end

  def create_user(attrs \\ %{}) do
    user_attrs =
      Enum.into(attrs, %{
        username: "testuser",
        discord_id: "123456789",
        avatar: "test_avatar.jpg"
      })

    %Soundboard.Accounts.User{}
    |> Soundboard.Accounts.User.changeset(user_attrs)
    |> Soundboard.Repo.insert()
  end

  def create_sound(user, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "test_sound#{System.unique_integer()}",
          file_path: setup_test_audio_file(),
          user_id: user.id
        },
        attrs
      )

    %Sound{}
    |> Sound.changeset(attrs)
    |> Repo.insert()
  end

  def create_tag(name) when is_binary(name) do
    %Tag{}
    |> Tag.changeset(%{name: name})
    |> Repo.insert()
  end
end
