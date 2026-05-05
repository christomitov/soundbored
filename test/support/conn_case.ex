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

  defmacro file_upload(view, upload_name, entries) do
    quote do
      file_input(unquote(view), "#upload-form", unquote(upload_name), unquote(entries))
    end
  end
end
