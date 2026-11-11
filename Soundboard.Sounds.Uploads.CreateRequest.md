# `Soundboard.Sounds.Uploads.CreateRequest`

The input to create a sound, built from request params (`new/2`).

A local file only comes in as a `%Plug.Upload{}`, the file Plug received
in the request; any other `file`/`upload` param (such as a map naming a
server path) is ignored, so a client can never make the server copy one of
its own files. Callers that already hold a received file (the LiveView's
consumed upload entry) attach it with `put_upload/2`.

# `t`

```elixir
@type t() :: %Soundboard.Sounds.Uploads.CreateRequest{
  default_volume_percent: String.t() | number() | nil,
  guild_id: String.t() | nil,
  is_join_sound: boolean() | String.t() | nil,
  is_leave_sound: boolean() | String.t() | nil,
  name: String.t() | nil,
  source_type: String.t() | nil,
  tags: [map() | String.t()] | nil,
  upload: upload() | nil,
  url: String.t() | nil,
  user: Soundboard.Accounts.User.t() | nil,
  volume: String.t() | number() | nil
}
```

# `upload`

```elixir
@type upload() ::
  %Plug.Upload{content_type: term(), filename: term(), path: term()}
  | %{
      optional(:path) =&gt; String.t(),
      optional(:filename) =&gt; String.t(),
      optional(:client_name) =&gt; String.t(),
      optional(String.t()) =&gt; String.t()
    }
```

# `new`

```elixir
@spec new(Soundboard.Accounts.User.t() | nil, map()) :: t()
```

# `put_upload`

```elixir
@spec put_upload(t(), upload() | nil) :: t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
