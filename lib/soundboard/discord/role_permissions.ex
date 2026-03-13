defmodule Soundboard.Discord.RolePermissions do
  @moduledoc """
  Role-based permissions and cooldown checks for playback/upload and settings UI.
  """

  import Ecto.Query

  alias Soundboard.Accounts.User
  alias Soundboard.{Repo, Discord.RoleSetting}

  @cooldown_table :soundboard_role_play_cooldowns

  @type policy :: %{
          can_upload: boolean(),
          can_play: boolean(),
          cooldown_ms: non_neg_integer()
        }
  @type authorize_result ::
          :ok
          | {:error, :not_authenticated}
          | {:error, :forbidden}
          | {:error, {:cooldown_active, non_neg_integer()}}
          | {:error, :invalid_payload}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}

  @default_role_policy %{
    can_upload: true,
    can_play: true,
    cooldown_ms: 0
  }

  @env_settings_panel_role_ids "SOUNDBOARD_SETTINGS_PANEL_ROLE_IDS"

  @spec settings_panel_access?(User.t() | nil) :: boolean()
  def settings_panel_access?(%User{} = user) do
    allowed_role_ids = settings_panel_role_ids()
    user_roles = normalize_user_roles(user.discord_roles)

    case allowed_role_ids do
      [] ->
        true

      _ ->
        user_roles not in [nil, []] and
          not MapSet.disjoint?(MapSet.new(user_roles), MapSet.new(allowed_role_ids))
    end
  end

  def settings_panel_access?(_user), do: false

  @spec settings_panel_role_ids() :: [String.t()]
  def settings_panel_role_ids do
    Application.get_env(:soundboard, :settings_panel_role_ids, [])
      |> normalize_role_ids()
  end

  @spec list_role_settings() :: [RoleSetting.t()]
  def list_role_settings do
    list_role_settings_for_guild(guild_id())
  end

  @spec list_role_settings_for_guild(String.t() | nil) :: [RoleSetting.t()]
  def list_role_settings_for_guild(guild_id) when is_binary(guild_id) and guild_id != "" do
    from(s in RoleSetting, where: s.guild_id == ^guild_id, order_by: [asc: s.role_id])
    |> Repo.all()
  end

  def list_role_settings_for_guild(_), do: []

  @spec can_upload?(User.t() | nil) :: boolean()
  def can_upload?(%User{} = user), do: effective_policy(user).can_upload
  def can_upload?(_), do: false

  @spec authorize_upload(User.t() | nil) :: authorize_result()
  def authorize_upload(%User{} = user) do
    user
    |> effective_policy()
    |> case do
      %{can_upload: true} -> :ok
      _ -> {:error, :forbidden}
    end
  end

  def authorize_upload(_), do: {:error, :not_authenticated}

  @spec authorize_play(User.t() | nil) :: authorize_result()
  def authorize_play(%User{} = user) do
    case effective_policy(user) do
      %{can_play: false} ->
        {:error, :forbidden}

      %{cooldown_ms: cooldown_ms} ->
        check_and_record_play(user.id, cooldown_ms)
    end
  end

  def authorize_play(_), do: {:error, :not_authenticated}

  @spec effective_policy(User.t() | nil) :: policy()
  def effective_policy(%User{} = user) do
    settings = role_settings_for_user(user)
    apply_role_settings(@default_role_policy, settings)
  end

  def effective_policy(_), do: @default_role_policy

  @spec permission_message(atom() | {:cooldown_active, non_neg_integer()}) :: String.t()
  def permission_message(:not_authenticated), do: "Play/upload requires a signed-in user."
  def permission_message(:forbidden), do: "Access denied: missing required role permission."
  def permission_message({:cooldown_active, milliseconds}) when is_integer(milliseconds),
    do: "Playback is cooling down. Please wait #{milliseconds}ms."
  def permission_message({:error, reason}), do: permission_message(reason)
  def permission_message(_), do: "Action not allowed."

  @spec serialize_user_roles([String.t()] | String.t() | nil) :: String.t()
  def serialize_user_roles(role_ids), do: role_ids |> normalize_role_ids() |> Enum.join(",")

  @spec normalize_user_roles(String.t() | [String.t()] | nil) :: [String.t()]
  def normalize_user_roles(roles), do: normalize_role_ids(roles)

  @spec save_role_setting(map()) :: authorize_result()
  def save_role_setting(%{} = attrs) do
    guild_id = guild_id()

    with {:ok, normalized_attrs} <- normalize_role_setting_attrs(guild_id, attrs) do
      role_id = normalized_attrs[:role_id]

      role_setting =
        Repo.get_by(RoleSetting, guild_id: guild_id, role_id: role_id) || %RoleSetting{}

      role_setting
      |> RoleSetting.changeset(normalized_attrs)
      |> Repo.insert_or_update()
    end
  end

  def save_role_setting(_), do: {:error, :invalid_payload}

  @spec delete_role_setting(String.t() | nil) :: authorize_result()
  def delete_role_setting(role_id) when is_binary(role_id) do
    role_id = normalize_single_role_id(role_id)
    guild_id = guild_id()

    case Repo.get_by(RoleSetting, guild_id: guild_id, role_id: role_id) do
      nil -> {:error, :not_found}
      setting -> Repo.delete(setting)
    end
  end

  def delete_role_setting(_), do: {:error, :invalid_payload}

  defp role_settings_for_user(%User{} = user) do
    guild_id = guild_id()
    role_ids = normalize_user_roles(user.discord_roles)

    case {guild_id, role_ids} do
      {guild_id, []} when is_binary(guild_id) and guild_id != "" ->
        []

      {guild_id, _} when is_binary(guild_id) and guild_id != "" ->
        from(s in RoleSetting,
          where: s.guild_id == ^guild_id and s.role_id in ^role_ids
        )
        |> Repo.all()

      _ ->
        []
    end
  end

  defp role_settings_for_user(_user), do: []

  defp apply_role_settings(policy, []), do: policy

  defp apply_role_settings(policy, settings) do
    settings
    |> Enum.reduce(policy, fn setting, acc ->
      %{
        can_upload: acc.can_upload && setting.can_upload,
        can_play: acc.can_play && setting.can_play,
        cooldown_ms: max(acc.cooldown_ms, setting.cooldown_ms || 0)
      }
    end)
  end

  defp check_and_record_play(user_id, cooldown_ms) when cooldown_ms <= 0 do
    :ok = record_play_time(user_id)
    :ok
  end

  defp check_and_record_play(user_id, cooldown_ms) when is_integer(cooldown_ms) and cooldown_ms > 0 do
    ensure_cooldown_table()

    now_ms = System.monotonic_time(:millisecond)

    case :ets.lookup(@cooldown_table, user_id) do
      [{^user_id, last_played_ms}] when is_integer(last_played_ms) ->
        elapsed_ms = now_ms - last_played_ms

        if elapsed_ms >= cooldown_ms do
          record_play_time(user_id)
          :ok
        else
          {:error, {:cooldown_active, cooldown_ms - elapsed_ms}}
        end

      _ ->
        record_play_time(user_id)
        :ok
    end
  end

  defp check_and_record_play(_, _), do: :ok

  defp record_play_time(user_id) when is_integer(user_id) do
    ensure_cooldown_table()
    :ets.insert(@cooldown_table, {user_id, System.monotonic_time(:millisecond)})
    :ok
  end

  defp record_play_time(_user_id), do: :ok

  defp ensure_cooldown_table do
    case :ets.whereis(@cooldown_table) do
      :undefined ->
        try do
          :ets.new(@cooldown_table, [:set, :public, :named_table])
        rescue
          _ -> :ok
        end

      _ ->
        :ok
    end
  end

  defp normalize_role_setting_attrs(nil, _), do: {:error, :invalid_payload}

  defp normalize_role_setting_attrs(guild_id, attrs) do
    role_id =
      attrs
      |> Map.get("role_id", attrs[:role_id])
      |> normalize_single_role_id()

    cooldown_ms = parse_cooldown_ms(Map.get(attrs, "cooldown_ms", attrs[:cooldown_ms]))

    normalized_attrs = %{
      "guild_id" => guild_id,
      "role_id" => role_id,
      "cooldown_ms" => cooldown_ms,
      "can_upload" => parse_bool(Map.get(attrs, "can_upload", attrs[:can_upload])),
      "can_play" => parse_bool(Map.get(attrs, "can_play", attrs[:can_play]))
    }

    if role_id == "" do
      {:error, :invalid_payload}
    else
      {:ok, normalized_attrs}
    end
  end

  defp parse_cooldown_ms(nil), do: 0

  defp parse_cooldown_ms(value) when is_integer(value), do: max(value, 0)

  defp parse_cooldown_ms(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> max(parsed, 0)
      _ -> 0
    end
  end

  defp parse_cooldown_ms(_), do: 0

  defp parse_bool(true), do: true
  defp parse_bool(false), do: false
  defp parse_bool("true"), do: true
  defp parse_bool("false"), do: false
  defp parse_bool("1"), do: true
  defp parse_bool("0"), do: false
  defp parse_bool(1), do: true
  defp parse_bool(0), do: false
  defp parse_bool(_), do: false

  defp normalize_role_ids(nil), do: []

  defp normalize_role_ids(role_ids) when is_binary(role_ids) do
    role_ids
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_role_ids(role_ids) when is_list(role_ids) do
    role_ids
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_role_ids(_), do: []

  defp normalize_single_role_id(nil), do: ""

  defp normalize_single_role_id(role_id) when is_binary(role_id) do
    role_id
    |> String.trim()
  end

  defp normalize_single_role_id(value), do: normalize_single_role_id(to_string(value))

  defp guild_id do
    Application.get_env(:soundboard, :oauth_required_guild_id)
    |> case do
      value when is_binary(value) -> String.trim(value)
      value when is_integer(value) -> Integer.to_string(value)
      _ -> ""
    end
  end
end
