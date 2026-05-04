# Implementation Plan: Custom Colors and Images for Sounds

This plan outlines the steps to add custom background colors and resized images to sound items, enhancing the UI with a more visual and responsive experience. We will use `ffmpeg` for image processing, as it is already a requirement for the project's audio features.

## 1. Dependencies and Environment
- No new system dependencies are required, as `ffmpeg` is already installed.
- No new Elixir dependencies are required. We will use `System.cmd/3` to invoke `ffmpeg`.

## 2. Database & Schema
- Create a migration `add_appearance_to_sounds`:
  - `ALTER TABLE sounds ADD COLUMN color TEXT;`
  - `ALTER TABLE sounds ADD COLUMN image_filename TEXT;`
- Update `Soundboard.Sound` schema:
  - Add `field :color, :string`
  - Add `field :image_filename, :string`
  - Update `changeset/2` to include these fields in `cast/3`.

## 3. Image Processing Logic
- Create/Update a service (e.g., `Soundboard.Sounds.ImageProcessing`) to handle resizing and conversion:
  - **Format**: All uploaded images will be converted to **PNG**.
  - **Fitting**: Resize and crop the image to a target aspect ratio that works for both landscape (grid view) and square (list view).
  - **Standard Size**: 400x300px (4:3) is a good middle ground, or we can generate a 400x400 square and use CSS `object-cover` to display it as landscape. 
  - **FFmpeg Command**:
    - `ffmpeg -i <input> -vf "scale=400:400:force_original_aspect_ratio=increase,crop=400:400" <output>.png`
  - Save the processed image to `priv/static/uploads/images/`.

## 4. LiveView Integration (Upload)
- Update `SoundboardWeb.Live.SoundboardLive`:
  - Add `allow_upload(:image, accept: ~w(.jpg .jpeg .png .webp), max_entries: 1)` in `mount/3`.
- Update `SoundboardWeb.Live.SoundboardLive.UploadFlow`:
  - Add `image_color` and `image_upload` handling to the state.
  - In `save/3`, consume the `:image` upload, process it via the image service, and include the `image_filename` and `color` in the `create_sound` attributes.

## 5. LiveView Integration (Edit)
- Update `SoundboardWeb.Live.SoundboardLive.EditFlow`:
  - Allow updating the `color` and replacing the `image`.
  - Handle deletion of old image files when replaced or when the sound is deleted.

## 6. UI Enhancements
- **Modals (`UploadModal`, `EditModal`)**:
  - Add a color input (e.g., `<input type="color">` or a set of preset Tailwind color buttons).
  - Add the `live_file_input` for the `:image` upload.
- **Sound Card (`soundboard_live.html.heex`)**:
  - Apply the background color dynamically: `style={"background-color: #{sound.color}"}`.
  - Implement responsive image display:
    - If `show_images` is true:
      - On large screens (grid): Image at top of card, full width, fixed aspect ratio.
      - On small screens (list): Image on the left as a 64x64px square.
- **Global Toggle**:
  - Add a "Show Images" toggle in the soundboard header.
  - Track this in the LiveView session/assigns.

## 8. Git Workflow
- Create a new branch: `feature/sound-appearance-enhancements`.
- Commit changes incrementally.
- Prepare to create a new PR upon completion.
