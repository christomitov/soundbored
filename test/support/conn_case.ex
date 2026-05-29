defmodule SoundboardWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate
  require Phoenix.LiveViewTest
  @endpoint SoundboardWeb.Endpoint

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import SoundboardWeb.ConnCase
      import Soundboard.TestHelpers

      alias SoundboardWeb.Router.Helpers, as: Routes

      # The default endpoint for testing
      @endpoint SoundboardWeb.Endpoint

      use SoundboardWeb, :verified_routes
    end
  end

  setup tags do
    Soundboard.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def file_upload(lv, field, entries) do
    {entries, _refs} =
      Enum.reduce(entries, {[], []}, fn entry, {entries, refs} ->
        ref = entry[:ref] || "phx-#{System.unique_integer()}"

        entry =
          Map.merge(
            %{
              name: "test.mp3",
              content: "test",
              size: 9999,
              type: "audio/mpeg",
              ref: ref,
              done?: true
            },
            entry
          )

        {[entry | entries], [ref | refs]}
      end)

    entries = Enum.reverse(entries)

    for entry <- entries do
      Phoenix.LiveViewTest.file_input(lv, field, entry, entry.ref)
    end
  end
end
