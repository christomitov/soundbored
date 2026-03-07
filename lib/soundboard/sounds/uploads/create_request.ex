defmodule Soundboard.Sounds.Uploads.CreateRequest do
  @moduledoc false

  alias Soundboard.Accounts.User

  @enforce_keys [:user]
  defstruct [
    :user,
    :source_type,
    :name,
    :url,
    :upload,
    :tags,
    :volume,
    :is_join_sound,
    :is_leave_sound,
    :default_volume_percent
  ]

  @type upload ::
          %Plug.Upload{}
          | %{
              optional(:path) => String.t(),
              optional(:filename) => String.t(),
              optional(:client_name) => String.t(),
              optional(String.t()) => String.t()
            }

  @type t :: %__MODULE__{
          user: User.t() | nil,
          source_type: String.t() | nil,
          name: String.t() | nil,
          url: String.t() | nil,
          upload: upload() | nil,
          tags: [map() | String.t()] | nil,
          volume: String.t() | number() | nil,
          is_join_sound: boolean() | String.t() | nil,
          is_leave_sound: boolean() | String.t() | nil,
          default_volume_percent: String.t() | number() | nil
        }

  @spec new(User.t() | nil, map()) :: t()
  def new(user, attrs \\ %{}) when is_map(attrs) do
    %__MODULE__{
      user: user,
      source_type: get_param(attrs, :source_type),
      name: get_param(attrs, :name),
      url: get_param(attrs, :url),
      upload: normalize_upload(get_param(attrs, :upload) || get_param(attrs, :file)),
      tags: get_param(attrs, :tags) || get_param(attrs, "tags[]") || [],
      volume: get_param(attrs, :volume),
      is_join_sound: get_param(attrs, :is_join_sound),
      is_leave_sound: get_param(attrs, :is_leave_sound),
      default_volume_percent: get_param(attrs, :default_volume_percent)
    }
  end

  @spec put_upload(t(), upload() | nil) :: t()
  def put_upload(%__MODULE__{} = request, upload) do
    struct!(request, upload: normalize_upload(upload))
  end

  defp normalize_upload(nil), do: nil

  defp normalize_upload(upload) when is_map(upload) do
    %{
      path: get_param(upload, :path),
      filename: get_param(upload, :filename) || get_param(upload, :client_name)
    }
  end

  defp normalize_upload(_), do: nil

  defp get_param(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end
end
