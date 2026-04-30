# Spec: Custom Colors and Images for Sound Cards

**Status:** Implemented  
**Date:** 2026-04-30  
**Author:** Justin Hart

---

## Summary

Sound cards in the web UI can now display a custom background color and an uploaded image. A global "Show/Hide Images" toggle controls whether images render at all. Images are processed server-side via ffmpeg into a fixed 400×300 PNG and served as static files. Two security issues in the existing upload pipeline were fixed in the same pass: path traversal via user-supplied sound names and uncontained write paths.

---

## Motivation

The soundboard grid is a uniform grid of identically styled cards. Users with many sounds have no visual way to group or distinguish them at a glance. Color and image allow personal expression and make the board easier to navigate — a user can immediately spot "the one with the cat photo" without reading filenames.

Images were also a natural place to harden the upload pipeline: the work required touching `UploadsPath` and `Source`, which surfaced existing path-traversal and unsanitized-name issues.

---

## User-Facing Behavior

### Color

- Each sound has an optional background color, set via a `<input type="color">` picker in the upload and edit modals.
- Defaults to the card's normal background when unset (no color stored → no `style` attribute).
- When a color is set, text and icon colors on the card switch to dark variants (`text-gray-900`, `hover:text-green-700`, etc.) to maintain contrast against an unknown background.

### Image

- Each sound has an optional image, uploaded via a file picker in the upload and edit modals.
- Accepted formats: JPG, JPEG, PNG, WebP. Max size: 5 MB.
- Images are converted to PNG and resized/cropped to 400×300 by the server; the original file is never stored.
- Served from `/uploads/images/<uuid>.png`.
- Uploading a new image during an edit replaces the previous image (old file deleted).
- An existing image can be cleared without uploading a replacement via a `×` button overlaid on the preview in the edit modal. The preview disappears immediately; the file input remains so a replacement can be uploaded in the same save.
- If both "remove" and a new upload occur in the same save, the new upload wins.
- Deleting a sound deletes its image file.

### Card Layout

Cards adapt based on whether `show_images` is true and whether the sound has an image:

| Context | Layout |
|---|---|
| Grid (≥ sm), image present, images shown | Full-width 16:9 image above the card content |
| List (< sm), image present, images shown | 64×64px square thumbnail inline-left of the title |
| No image, or images hidden | Content-only layout (unchanged from before) |

### Show/Hide Images Toggle

- A button in the soundboard header toggles image visibility globally for the session.
- State is held in LiveView assigns (`show_images`), not persisted across page loads.
- Button label reflects current state: "Hide Images" when on, "Show Images" when off.

---

## Architecture & Design

### Image Processing

All image handling lives in `Soundboard.Sounds.ImageProcessing`. It wraps ffmpeg directly via `System.cmd/3`, matching the existing pattern for audio processing.

**Processing pipeline:**
1. Receive the temp file path from `Phoenix.LiveView.consume_uploaded_entries/3`.
2. Generate a UUID filename (`Ecto.UUID.generate() <> ".png"`) — the original client filename is discarded entirely.
3. Run: `ffmpeg -i <tmp> -vf "scale=400:300:force_original_aspect_ratio=increase,crop=400:300" -y <dest>.png`
4. Write to `priv/static/uploads/images/`.
5. Return `{:ok, filename}` or `{:error, reason}`.

The UUID approach was chosen over a name-derived filename for two reasons: the original filename is user-controlled (path traversal risk), and since we always produce PNG output the original name carries no useful information.

**Deletion:**
`delete_image/1` is called in three situations:
- `Management.update_sound/3` — when a new image replaces the old one, the old file is deleted after the DB update succeeds.
- `Management.update_sound/3` — when `clear_image` is true (user clicked `×` and saved without uploading a replacement), the old file is deleted and `image_filename` is set to `nil`.
- `Management.delete_sound/2` — when a sound is deleted.

All calls use the filename stored in the DB. `delete_image(nil)` and `delete_image("")` are no-ops.

### Upload Flow Integration

Image uploads go through `Phoenix.LiveView`'s upload system (`allow_upload :image`) independently of the audio upload. Both flows consume their respective entries during the same save event.

`UploadFlow` and `EditFlow` each have a private `process_image_upload/1` (or `/2`) that consumes the `:image` entries and returns `{filename | nil, socket}`. The result is merged into the sound params before calling `Sounds.create_sound` or `Sounds.update_sound`. If no image was uploaded, `image_filename` is `nil` and the existing value is preserved on edit.

The `image` upload config allows only image MIME types, caps at 5 MB, and limits to one entry.

### Data Flow: Upload

```
LiveView save event
  │
  ├─ process_image_upload → ImageProcessing.process_image(tmp_path)
  │                         → {:ok, "uuid.png"} | nil
  │
  ├─ params["color"] from form
  │
  ▼
CreateRequest → Normalizer → Source → Creator
  (color, image_filename threaded through each stage)
```

### Data Flow: Edit

```
LiveView save_sound event
  │
  ├─ process_image_upload → ImageProcessing.process_image(tmp_path)
  │                         → {:ok, "uuid.png"} | nil
  │
  ├─ priority cond:
  │    new upload present   → params["image_filename"] = new_filename
  │    clear_image == true  → params["clear_image"] = true
  │    otherwise            → params unchanged (management preserves existing)
  │
  ▼
Management.update_sound
  ├─ image_filename: new upload | nil (if clear) | existing (if unchanged)
  ├─ if new upload ≠ old, or clear_image → delete_image(old)
  └─ Repo.update (color, image_filename)
```

### Security Hardening

Two issues were fixed in `Source` as part of this work:

#### 1. Path traversal via sound name

`Source.prepare/2` constructs a destination filename as `params.name <> ext`. Previously `params.name` was used without sanitization, meaning a name like `"../../etc/cron.d/evil"` would produce a path outside `priv/static/uploads`.

**Fix — `sanitize_name/1`:** strips `/`, `\`, and null bytes via regex blocklist, trims whitespace, and truncates to 200 characters. Returns `{:error, changeset}` if the result is blank.

```elixir
@max_name_length 200

defp sanitize_name(name) do
  cleaned =
    (name || "")
    |> String.replace(~r/[\/\\\0]/, "")
    |> String.trim()
    |> String.slice(0, @max_name_length)

  if blank?(cleaned) do
    {:error, add_error(change(%Sound{}), :filename, "can't be blank")}
  else
    {:ok, cleaned}
  end
end
```

#### 2. Unsafe path join in write paths

`copy_local_file/2` and `validate_destination_filename/1` both used `UploadsPath.file_path/1` (a plain `Path.join`) rather than `UploadsPath.safe_joined_path/1`, which expands both the base dir and the candidate path and verifies containment before returning.

**Fix:** both functions now use `safe_joined_path/1` and return `{:error, changeset}` on `:error` (traversal attempt). `upload_controller.ex` already used `safe_joined_path/1` for reads; the write path now matches.

Note: `sanitize_name/1` prevents traversal at the source; `safe_joined_path/1` is defense-in-depth at the write site.

---

## Database Changes

Migration: `20260430202700_add_appearance_to_sounds`

```sql
ALTER TABLE sounds ADD COLUMN color TEXT;
ALTER TABLE sounds ADD COLUMN image_filename TEXT;
```

Both columns are nullable. No backfill needed — existing sounds display with no color or image.

---

## Configuration

No new config keys. The `priv/static/uploads/images/` directory must exist (created manually or via deployment scripts). ffmpeg is already a required system dependency.

---

## File Inventory

| File | Action |
|---|---|
| `priv/repo/migrations/20260430202700_add_appearance_to_sounds.exs` | **New** — adds `color` and `image_filename` columns |
| `lib/soundboard/sound.ex` | **Modify** — add `color` and `image_filename` fields and cast |
| `lib/soundboard/sounds/image_processing.ex` | **New** — ffmpeg image processing, UUID filename generation, deletion |
| `lib/soundboard/sounds/management.ex` | **Modify** — delete old image on replace; delete image on sound delete; pass `color` and `image_filename` through update |
| `lib/soundboard/sounds/uploads/create_request.ex` | **Modify** — add `color` and `image_filename` to request struct and type spec |
| `lib/soundboard/sounds/uploads/creator.ex` | **Modify** — pass `color` and `image_filename` to sound attrs |
| `lib/soundboard/sounds/uploads/normalizer.ex` | **Modify** — thread `color` and `image_filename` through normalize |
| `lib/soundboard/sounds/uploads/source.ex` | **Modify** — add `sanitize_name/1`; switch `copy_local_file` and `validate_destination_filename` to `safe_joined_path` |
| `lib/soundboard_web/components/soundboard/edit_modal.ex` | **Modify** — add color picker, image preview, image `live_file_input`; add `uploads` attr |
| `lib/soundboard_web/components/soundboard/upload_modal.ex` | **Modify** — add color picker and image `live_file_input` |
| `lib/soundboard_web/live/soundboard_live.ex` | **Modify** — `allow_upload :image`; `show_images` assign; `toggle_images` handler |
| `lib/soundboard_web/live/soundboard_live.html.heex` | **Modify** — card color via inline style; responsive image layout; color-aware icon/tag colors; Show/Hide Images button |
| `lib/soundboard_web/live/soundboard_live/edit_flow.ex` | **Modify** — `process_image_upload/1`; `clear_image` state field; `remove_image/1` handler; priority cond in `save_sound/2` |
| `lib/soundboard_web/live/soundboard_live/upload_flow.ex` | **Modify** — `process_image_upload/2`; `upload_color` and `image_filename` state; pass both to `create_sound` |
| `test/soundboard/sounds/image_processing_test.exs` | **New** — ffmpeg processing, resize verification, deletion |
| `test/soundboard/sounds/uploads_test.exs` | **Modify** — name sanitization tests: slash/backslash/null stripping, whitespace trimming, length truncation, blank-after-strip error |

---

## Testing Strategy

| Layer | What is tested |
|---|---|
| `ImageProcessing` | `process_image/1` converts to PNG and resizes to 400×300 (verified via `ffprobe`). `delete_image/1` handles `nil`, `""`, and existing file. |
| `Uploads` — name sanitization | Forward slashes stripped. Backslashes stripped. Null bytes stripped. Whitespace trimmed. 201-char name truncated to 200. Name of only slashes returns blank error. `nil` name returns blank error. Sanitization applies to local uploads (file written to non-traversal path). |
| Manual / visual | Color applied to card background. Text and icon colors adjust for colored cards. Image renders in landscape (grid) and thumbnail (list) layout. Toggle hides/shows all images. Uploading an image during edit replaces the previous one. Clicking `×` clears the preview; saving without a new upload sets `image_filename` to `nil` and deletes the file. Uploading after clicking `×` uses the new upload (new upload wins). Deleting a sound removes its image. |

---

## Security Considerations

- **UUID filenames for images:** client-supplied filenames are discarded. No user input reaches the filesystem for image storage.
- **Sound name sanitization:** path separators and null bytes are stripped before the name is used as a filename component. This prevents path traversal even if `safe_joined_path` were bypassed.
- **Defense-in-depth for writes:** `safe_joined_path/1` contains all write operations within `priv/static/uploads`. An attacker supplying a traversal string hits two independent checks.
- **Image MIME allowlist:** `allow_upload :image` restricts accepted types to `.jpg .jpeg .png .webp`, enforced by LiveView before the file reaches `ImageProcessing`.
- **5 MB cap:** prevents large files from being written to disk.

---

## Out of Scope

- **Persisting the Show/Hide Images preference** across page loads or users (currently session-only).
- **Per-user image visibility preferences** (toggle is global to the session).
- **Image CDN or object storage** — images are served as static files from `priv/static/`. Suitable for self-hosted deployments; would need revisiting for multi-node or high-traffic deployments.
- **Animated GIFs** — ffmpeg's crop/scale pipeline converts them to a static PNG.
- **Character allowlist for sound names** — current approach is a blocklist (strip dangerous chars). A future pass could tighten this to alphanumeric + a safe set.
