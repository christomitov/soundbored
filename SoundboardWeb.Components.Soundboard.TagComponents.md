# `SoundboardWeb.Components.Soundboard.TagComponents`

Shared tag UI helpers for the soundboard modals.

# `tag_badge_list`

## Attributes

* `tags` (`:list`) - Defaults to `[]`.
* `remove_event` (`:string`) (required)
* `tag_key` (`:atom`) - Defaults to `:name`.
* `wrapper_class` (`:string`) - Defaults to `"mt-2 flex flex-wrap gap-2"`.

# `tag_filter_button`

## Attributes

* `tag` (`:any`) (required)
* `selected_tags` (`:list`) (required)
* `uploaded_files` (`:list`) (required)
* `tag_key` (`:atom`) - Defaults to `:name`.
* `click_event` (`:string`) - Defaults to `"toggle_tag_filter"`.
* `class` (`:any`) - Defaults to `[]`.

# `tag_input_field`

## Attributes

* `value` (`:string`) - Defaults to `""`.
* `placeholder` (`:string`) - Defaults to `"Type a tag and press Enter..."`.
* `input_id` (`:string`) - Defaults to `nil`.
* `disabled` (`:boolean`) - Defaults to `false`.
* `class` (`:string`) - Defaults to `""`.
* `onkeydown` (`:string`) - Defaults to `nil`.
* `autocomplete` (`:string`) - Defaults to `nil`.
* Global attributes are accepted.

# `tag_suggestions_dropdown`

## Attributes

* `tag_input` (`:string`) - Defaults to `""`.
* `tag_suggestions` (`:list`) - Defaults to `[]`.
* `select_event` (`:string`) (required)
* `tag_key` (`:atom`) - Defaults to `:name`.
* `wrapper_class` (`:string`) - Defaults to `"absolute z-10 mt-1 w-full bg-white dark:bg-gray-700 shadow-lg max-h-60 rounded-md py-1 text-base overflow-auto focus:outline-none sm:text-sm"`.
* `suggestion_class` (`:string`) - Defaults to `"w-full text-left px-4 py-2 text-sm hover:bg-blue-50 dark:hover:bg-blue-900 dark:text-gray-100"`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
