defmodule SoundboardWeb.Components.Soundboard.UploadModal do
  @moduledoc """
  The upload modal component.
  """
  use Phoenix.Component
  alias SoundboardWeb.Components.Soundboard.{TagComponents, VolumeControl}

  def upload_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity z-10">
      <div class="fixed inset-0 z-10 overflow-y-auto">
        <div class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
          <div class="relative transform overflow-hidden rounded-lg bg-white dark:bg-gray-800 px-4 pb-4 pt-5 text-left shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-lg sm:p-6">
            <div class="absolute right-0 top-0 pr-4 pt-4">
              <button
                phx-click="close_upload_modal"
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
                Add Sound
              </h3>

              <form
                phx-submit="save_upload"
                phx-change="validate_upload"
                id="upload-form"
                class="mt-4"
              >
                <!-- Source Type -->
                <div class="mb-4">
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 text-left">
                    Source Type
                  </label>
                  <select
                    name="source_type"
                    phx-change="change_source_type"
                    class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 shadow-sm
                           focus:border-blue-500 focus:ring-blue-500 sm:text-sm
                           dark:bg-gray-700 dark:text-gray-100"
                  >
                    <option value="local" selected={@source_type == "local"}>Local File</option>
                    <option value="url" selected={@source_type == "url"}>URL</option>
                  </select>
                </div>

                <%= if @source_type == "local" do %>
                  <!-- Local File Input -->
                  <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 text-left mb-2">
                      File
                    </label>
                    <div class="flex items-center gap-2">
                      <.live_file_input
                        upload={@uploads.audio}
                        id="upload-audio-input"
                        class="block w-full text-sm text-gray-500 dark:text-gray-400
                               file:mr-4 file:py-2 file:px-4
                               file:rounded-md file:border-0
                               file:text-sm file:font-semibold
                               file:bg-blue-50 file:text-blue-700
                               dark:file:bg-blue-900 dark:file:text-blue-300
                               hover:file:bg-blue-100 dark:hover:file:bg-blue-800"
                      />
                    </div>
                  </div>
                <% else %>
                  <!-- URL Input -->
                  <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 text-left">
                      URL
                    </label>
                    <input
                      type="url"
                      name="url"
                      value={@url}
                      required
                      id="upload-url-input"
                      placeholder="https://example.com/sound.mp3"
                      phx-change="validate_upload"
                      phx-debounce="400"
                      class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 shadow-sm
                             focus:border-blue-500 focus:ring-blue-500 sm:text-sm
                             dark:bg-gray-700 dark:text-gray-100"
                    />
                  </div>
                <% end %>
                
    <!-- Details: shown but inputs are disabled until a file/URL is provided -->
                  <!-- Name Input -->
                <div class="mb-4">
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 text-left">
                    Name
                  </label>
                  <input
                    type="text"
                    name="name"
                    value={@upload_name}
                    required
                    placeholder="Sound name"
                    phx-change="validate_upload"
                    phx-debounce="400"
                    disabled={
                      (@source_type == "local" and @uploads.audio.entries == []) or
                        (@source_type == "url" and String.trim(@url || "") == "")
                    }
                    class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 shadow-sm
                             focus:border-blue-500 focus:ring-blue-500 sm:text-sm
                             dark:bg-gray-700 dark:text-gray-100 disabled:opacity-50 disabled:cursor-not-allowed"
                  />
                  <%= if (@source_type == "local" and @uploads.audio.entries == []) do %>
                    <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                      Select a file first to name it.
                    </p>
                  <% end %>
                  <%= if (@source_type == "url" and String.trim(@url || "") == "") do %>
                    <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                      Enter a URL first to name it.
                    </p>
                  <% end %>
                  <%= if @upload_error do %>
                    <p class="mt-1 text-sm text-red-600 dark:text-red-400">{@upload_error}</p>
                  <% end %>
                </div>
                
    <!-- Tags -->
                <div class="text-left">
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Tags
                  </label>
                  <TagComponents.tag_badge_list tags={@upload_tags} remove_event="remove_upload_tag" />

                  <div class="mt-2 relative">
                    <div>
                      <TagComponents.tag_input_field
                        value={@upload_tag_input}
                        placeholder="Type a tag and press Enter or Tab..."
                        input_id="upload-tag-input"
                        disabled={
                          (@source_type == "local" and @uploads.audio.entries == []) or
                            (@source_type == "url" and String.trim(@url || "") == "")
                        }
                        phx-keyup="upload_tag_input"
                        phx-keydown="add_upload_tag"
                        phx-value-value={@upload_tag_input}
                        onkeydown="
                          if(event.key === 'Enter' || event.key === 'Tab') {
                            event.preventDefault();
                          }
                        "
                        class="disabled:opacity-50 disabled:cursor-not-allowed"
                        autocomplete="off"
                      />
                    </div>

                    <TagComponents.tag_suggestions_dropdown
                      tag_input={@upload_tag_input}
                      tag_suggestions={@upload_tag_suggestions}
                      select_event="select_upload_tag"
                    />
                  </div>
                </div>

                <% preview_kind = if @source_type == "local", do: "local-upload", else: "url" %>
                <% preview_disabled =
                  if @source_type == "local" do
                    @uploads.audio.entries == []
                  else
                    String.trim(@url || "") == ""
                  end %>
                <VolumeControl.volume_control
                  id="upload-volume-control"
                  value={@upload_volume}
                  target="upload"
                  data-preview-kind={preview_kind}
                  data-file-input-id={
                    if preview_kind == "local-upload", do: "upload-audio-input", else: nil
                  }
                  data-url-input-id={if preview_kind == "url", do: "upload-url-input", else: nil}
                  data-preview-src={if preview_kind == "url", do: @url, else: nil}
                  preview_disabled={preview_disabled}
                />
                
    <!-- Sound Settings -->
                <div class="mt-5 mb-4">
                  <div class="flex flex-col gap-3 text-left">
                    <label class="relative flex items-start">
                      <div class="flex h-6 items-center">
                        <input
                          type="checkbox"
                          name="is_join_sound"
                          value="true"
                          checked={@is_join_sound}
                          phx-click="toggle_join_sound"
                          disabled={
                            (@source_type == "local" and @uploads.audio.entries == []) or
                              (@source_type == "url" and String.trim(@url || "") == "")
                          }
                          class="h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-600 dark:border-gray-600 dark:focus:ring-offset-gray-800"
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
                          checked={@is_leave_sound}
                          phx-click="toggle_leave_sound"
                          disabled={
                            (@source_type == "local" and @uploads.audio.entries == []) or
                              (@source_type == "url" and String.trim(@url || "") == "")
                          }
                          class="h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-600 dark:border-gray-600 dark:focus:ring-offset-gray-800"
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

                <div class="mt-5 sm:mt-6">
                  <button
                    type="submit"
                    phx-disable-with="Adding..."
                    disabled={
                      (@source_type == "local" and @uploads.audio.entries == []) or
                        (@source_type == "url" and String.trim(@url || "") == "")
                    }
                    class="inline-flex w-full justify-center rounded-md bg-blue-600 px-3 py-2
                             text-sm font-semibold text-white shadow-sm hover:bg-blue-500
                             focus-visible:outline focus-visible:outline-2
                             focus-visible:outline-offset-2 focus-visible:outline-blue-600
                             dark:focus-visible:outline-offset-gray-800 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Add Sound
                  </button>
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
