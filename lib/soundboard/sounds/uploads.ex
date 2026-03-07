defmodule Soundboard.Sounds.Uploads do
  @moduledoc """
  Canonical sound upload/create API.
  """

  import Ecto.Changeset

  alias Soundboard.Sound
  alias Soundboard.Sounds.Uploads.{CreateRequest, Creator, Normalizer, Source}

  @type create_error :: Ecto.Changeset.t()
  @type create_result :: {:ok, Sound.t()} | {:error, create_error()}

  @spec validate(CreateRequest.t()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def validate(%CreateRequest{} = request) do
    with {:ok, params} <- Normalizer.normalize(request),
         {:ok, _source} <- Source.prepare(params, :validate) do
      {:ok, params}
    end
  end

  @spec create(CreateRequest.t()) :: create_result()
  def create(%CreateRequest{} = request) do
    with {:ok, params} <- Normalizer.normalize(request),
         {:ok, source} <- Source.prepare(params, :create),
         {:ok, sound} <- Creator.create(params, source) do
      {:ok, sound}
    else
      {:error, reason} -> {:error, normalize_create_error(reason)}
    end
  end

  @spec error_message(Ecto.Changeset.t() | String.t() | term()) :: String.t()
  def error_message(%Ecto.Changeset{} = changeset) do
    Enum.map_join(changeset.errors, ", ", fn
      {:filename, {"has already been taken", _}} -> "A sound with that name already exists"
      {:file, {"Please select a file", _}} -> "Please select a file"
      {key, {msg, _}} -> "#{key} #{msg}"
    end)
  end

  def error_message(error) when is_binary(error), do: error
  def error_message(_), do: "An unexpected error occurred"

  defp normalize_create_error(%Ecto.Changeset{} = changeset), do: changeset
  defp normalize_create_error(message) when is_binary(message), do: add_base_error(message)
  defp normalize_create_error(_reason), do: add_base_error("An unexpected error occurred")

  defp add_base_error(message) do
    change(%Sound{})
    |> add_error(:base, message)
  end
end
