defmodule SoundboardWeb.Components.Soundboard.EditModal do
  @moduledoc """
  The edit modal component.
  """
  use Phoenix.Component
  alias Soundboard.Volume
  alias SoundboardWeb.Components.Soundboard.{TagComponents, VolumeControl}

  def edit_modal(assigns) do
    assigns = assign_new(assigns, :flash, fn -> %{} end)

    # Ensure flash.error exists with nil default
    assigns = update(assigns, :flash, fn flash -> Map.put_new(flash, :error, nil) end)

    # Add a default empty list for tags if they're not loaded
    assigns =
      assign_new(assigns, :current_sound, fn ->
        %{tags: [], is_join_sound: false, is_leave_sound: false}
      end)

    # Ensure tags is a list even if not loaded
    assigns =
      update(assigns, :current_sound, fn sound ->
        tags =
          case sound.tags do
            tags when is_list(tags) -> tags
            _ -> []
          end

        Map.put(sound, :tags, tags)
      end)

    # Add default assigns for validation error
    assigns =
      assigns
      |> assign_new(:validation_error, fn -> nil end)

    ~H"""
    <div
      class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity z-10"
      phx-window-keydown="close_modal_key"
      phx-key="Escape"
    >
      <div class="fixed inset-0 z-10 overflow-y-auto">
        <div class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
          <div class="relative transform overflow-hidden rounded-lg bg-white dark:bg-gray-800 px-4 pb-4 pt-5 text-left shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-lg sm:p-6">
            <div class="absolute right-0 top-0 pr-4 pt-4">
              <button
                phx-click="close_modal"
                type="button"
                class="rounded-md bg-white dark:bg-gray-800 text-gray-400 hover:text-gray-500 dark:hover:text-gray-300"
              >
                <span class="sr-only">Close</span>
                <svg
                  class="h-6 w-6"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <div class="mt-3 text-center sm:mt-5">
              <h3 class="text-base font-semibold leading-6 text-gray-900 dark:text-gray-100 mb-4">
                Edit Sound
              </h3>

              <form phx-submit="save_sound" phx-change="validate_sound" id="edit-form" class="mt-4">
                <input type="hidden" name="sound_id" value={@current_sound.id} />
                <input type="hidden" name="source_type" value={@current_sound.source_type} />
                <input type="hidden" name="url" value={@current_sound.url} />
                
    <!-- Display current source type (non-editable) -->
                <div class="mb-4 text-left">
                  <label class="block text-sm font-medium text-gray-500 dark:text-gray-400">
                    Source
                  </label>
                  <div class="mt-1 text-sm text-gray-700 dark:text-gray-300">
                    <%= if @current_sound.source_type == "url" do %>
                      URL: {@current_sound.url}
                    <% else %>
                      Local File
                    <% end %>
                  </div>
                </div>
                
    <!-- Name Input with error message -->
                <div class="mb-4">
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 text-left">
                    Name
                  </label>
                  <input
                    type="text"
                    name="filename"
                    value={
                      String.replace(
                        @current_sound.filename,
                        Path.extname(@current_sound.filename),
                        ""
                      )
                    }
                    required
                    placeholder="Sound name"
                    phx-debounce="400"
                    class={"mt-1 block w-full rounded-md shadow-sm sm:text-sm
                           dark:text-gray-100 #{if @flash && @flash.error, do: "border-red-300 focus:border-red-500 focus:ring-red-500", else: "border-gray-300 dark:border-gray-600 focus:border-blue-500 focus:ring-blue-500"}
                           dark:bg-gray-700"}
                  />
                  <%= if @flash && @flash.error do %>
                    <p class="mt-2 text-sm text-red-600 dark:text-red-400">{@flash.error}</p>
                  <% end %>
                </div>

                <% volume_percent = Volume.decimal_to_percent(@current_sound.volume) %>
                <% preview_kind = if @current_sound.source_type == "url", do: "url", else: "existing" %>
                <% preview_src =
                  if preview_kind == "existing",
                    do: "/uploads/#{@current_sound.filename}",
                    else: @current_sound.url %>
                <VolumeControl.volume_control
                  id="edit-volume-control"
                  value={volume_percent}
                  target="edit"
                  data-preview-kind={preview_kind}
                  data-preview-src={preview_src}
                  preview_disabled={is_nil(preview_src) or preview_src == ""}
                />
                
    <!-- Tags -->
                <div class="text-left">
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Tags
                  </label>
                  <TagComponents.tag_badge_list tags={@current_sound.tags} remove_event="remove_tag" />
                </div>
                
    <!-- Tag Input -->
                <div class="mt-2 relative">
                  <div>
                    <TagComponents.tag_input_field
                      value={@tag_input}
                      placeholder="Type a tag and press Enter..."
                      input_id="tag-input"
                      phx-keyup="tag_input"
                      phx-keydown="add_tag"
                      phx-value-value={@tag_input}
                      onkeydown="
                        if(event.key === 'Enter') {
                          event.preventDefault();
                          const value = this.value;
                          requestAnimationFrame(() => this.value = '');
                          return false;
                        }
                      "
                      autocomplete="off"
                    />
                  </div>

                  <TagComponents.tag_suggestions_dropdown
                    tag_input={@tag_input}
                    tag_suggestions={@tag_suggestions}
                    select_event="select_tag"
                  />
                </div>
                
    <!-- Sound Settings -->
                <div class="mt-5 mb-4">
                  <div class="flex flex-col gap-3 text-left">
                    <% user_setting =
                      Enum.find(
                        @current_sound.user_sound_settings || [],
                        &(&1.user_id == @current_user.id)
                      ) %>
                    <label class="relative flex items-start">
                      <div class="flex h-6 items-center">
                        <input
                          type="checkbox"
                          name="is_join_sound"
                          value="true"
                          checked={user_setting && user_setting.is_join_sound}
                          class="h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-600"
                        />
                      </div>
                      <div class="ml-3 text-sm leading-6">
                        <span class="font-medium text-gray-900 dark:text-gray-100">
                          Play when I join voice
                        </span>
                      </div>
                    </label>

                    <label class="relative flex items-start">
                      <div class="flex h-6 items-center">
                        <input
                          type="checkbox"
                          name="is_leave_sound"
                          value="true"
                          checked={user_setting && user_setting.is_leave_sound}
                          class="h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-600"
                        />
                      </div>
                      <div class="ml-3 text-sm leading-6">
                        <span class="font-medium text-gray-900 dark:text-gray-100">
                          Play when I leave voice
                        </span>
                      </div>
                    </label>
                  </div>
                </div>

                <div class="mt-5 sm:mt-6 flex gap-3">
                  <button
                    type="submit"
                    disabled={@flash && @flash.error}
                    class={"flex-1 rounded-md px-3 py-2 text-sm font-semibold text-white shadow-sm
                            #{if @flash && @flash.error,
                              do: "bg-gray-400 cursor-not-allowed",
                              else: "bg-blue-600 hover:bg-blue-500"}"}
                  >
                    Save Changes
                  </button>
                  <%= if @current_sound.user_id == @current_user.id do %>
                    <button
                      type="button"
                      phx-click="show_delete_confirm"
                      class="flex-1 rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500"
                    >
                      Delete Sound
                    </button>
                  <% end %>
                </div>
              </form>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
