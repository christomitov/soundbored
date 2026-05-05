# Fixes: Sound Appearance Post-Review Issues

Issues identified during code review of `feature/sound-appearance-enhancements` that did not block merge but should be addressed.

## 1. ✓ Validate color format in changeset

- In `Soundboard.Sound.changeset/2`, add `validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/)` after the cast.
- Prevents CSS injection via crafted HTTP requests setting `color` to arbitrary strings (e.g. `red; display: none`).

## 2. ✓ Use `safe_joined_path` in `management.ex` rename

- In `lib/soundboard/sounds/management.ex`, replace `UploadsPath.file_path/1` with `UploadsPath.safe_joined_path/1` for `old_path` and `new_path` in the audio file rename logic.
- The PR hardened `source.ex` but left the edit rename path using the unsafe plain `Path.join`.

## 3. Fix `consume_uploaded_entries` return unwrap

- In `lib/soundboard_web/live/soundboard_live/upload_flow.ex` and `edit_flow.ex`, change the pattern match after `consume_uploaded_entries` from `[filename]` to `[{:ok, filename}]`.
- The callback returns `{:ok, filename}`, so the list element is the tuple; the current code binds `filename = {:ok, "uuid.png"}` and stores the tuple in the DB.

## 4. Move `maybe_cleanup_old_image` outside the transaction

- In `lib/soundboard/sounds/management.ex`, move the `maybe_cleanup_old_image` call to after the `Repo.transaction` block succeeds.
- Currently it deletes the file inside the transaction; a subsequent `Repo.rollback` leaves the DB referencing a deleted file.

## 5. Clean up orphaned image on create failure

- In `lib/soundboard_web/live/soundboard_live/upload_flow.ex`, add cleanup of the processed image file if `Sounds.create_sound` returns an error.
- Mirror the cleanup pattern used for audio files on transaction failure.

## 6. Use `UploadsPath` for image paths in `ImageProcessing`

- Replace `@images_dir "priv/static/uploads/images"` with resolution via `UploadsPath` (or `Application.app_dir(:soundboard, "priv/static/uploads/images")`).
- The relative path fails in Mix releases where the process CWD is not the project root.

## 7. Update `upload_color` assign from form params

- In `lib/soundboard_web/live/soundboard_live/upload_flow.ex`, update `assign_params` (or the `validate_upload` handler) to extract `params["color"]` and update the `upload_color` assign.
- Currently the color picker display is frozen at `#ffffff` on re-renders (e.g. after a name validation error), even though the correct value is submitted at save time.
