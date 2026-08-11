defmodule SoundboardWeb.Layouts do
  @moduledoc false
  use SoundboardWeb, :html

  import SoundboardWeb.Components.NowPlayingToast
  import SoundboardWeb.Components.Layouts.Transport

  embed_templates "layouts/*"
end
