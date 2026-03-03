defmodule Soundboard.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias SoundboardWeb.Live.PresenceHandler
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Soundboard Application")

    ensure_dave_runtime!()

    # Initialize presence handler state
    PresenceHandler.init()

    # Base children that always start
    base_children = [
      SoundboardWeb.Telemetry,
      {Phoenix.PubSub, name: Soundboard.PubSub},
      SoundboardWeb.Presence,
      SoundboardWeb.Endpoint,
      {SoundboardWeb.AudioPlayer, []},
      Soundboard.Repo,
      SoundboardWeb.DiscordHandler.State
    ]

    # Add Discord bot only in non-test environments
    children =
      if Application.get_env(:soundboard, :env) != :test do
        # EDA gateway runs in its own OTP application.
        # We keep the handler GenServer for app-specific state/tasks.
        base_children ++ [SoundboardWeb.DiscordHandler]
      else
        base_children
      end

    opts = [strategy: :one_for_one, name: Soundboard.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp ensure_dave_runtime! do
    if Application.get_env(:soundboard, :env) != :test and Application.get_env(:eda, :dave, false) do
      maybe_build_dave_runtime!()

      unless EDA.Voice.Dave.Native.available?() do
        raise """
        EDA DAVE is enabled, but the native library is unavailable.
        Build it in `deps/eda/native/eda_dave` with `cargo build --release`,
        then copy the built artifact to `_build/<env>/lib/eda/priv/native/eda_dave.so`.
        You can temporarily disable DAVE with `EDA_DAVE=false`.
        """
      end
    end
  end

  defp maybe_build_dave_runtime! do
    if EDA.Voice.Dave.Native.available?() do
      :ok
    else
      case System.find_executable("cargo") do
        nil ->
          :ok

        cargo ->
          source_dir = Path.join(["deps", "eda", "native", "eda_dave"])
          env = Application.get_env(:soundboard, :env, :dev)
          target_dir = Path.join(["_build", Atom.to_string(env), "lib", "eda", "priv", "native"])
          target_file = Path.join(target_dir, "eda_dave.so")
          artifact_dir = Path.join([source_dir, "target", "release"])

          if File.dir?(source_dir) do
            case System.cmd(cargo, ["build", "--release"], cd: source_dir, stderr_to_stdout: true) do
              {_output, 0} ->
                File.mkdir_p!(target_dir)

                source_file =
                  Path.join(artifact_dir, "libeda_dave.so")
                  |> then(fn so ->
                    if File.exists?(so),
                      do: so,
                      else: Path.join(artifact_dir, "libeda_dave.dylib")
                  end)

                if File.exists?(source_file) do
                  File.cp!(source_file, target_file)
                end

              _ ->
                :ok
            end
          end
      end
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SoundboardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
