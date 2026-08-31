# `SoundboardWeb.Components.Soundboard.VolumeControl`

Shared volume slider with preview support for upload/edit modals.

# `volume_control`

## Attributes

* `id` (`:string`) - Defaults to `nil`.
* `value` (`:integer`) (required)
* `target` (`:string`) (required)
* `push_event` (`:string`) - Defaults to `"update_volume"`.
* `label` (`:string`) - Defaults to `"Volume"`.
* `input_name` (`:string`) - Defaults to `"volume"`.
* `preview_disabled` (`:boolean`) - Defaults to `false`.
* `preview_label` (`:string`) - Defaults to `"Preview"`.
* `max_percent` (`:integer`) - Defaults to `150`.
* Global attributes are accepted.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
