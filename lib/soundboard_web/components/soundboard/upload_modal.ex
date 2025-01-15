defmodule SoundboardWeb.Components.Soundboard.UploadModal do
  use Phoenix.Component
  import SoundboardWeb.Components.Soundboard.Helpers

  def upload_modal(assigns) do
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
                Upload Sound
              </h3>

              <form
                phx-submit="save_upload"
                phx-change="validate_upload"
                id="upload-form"
                class="mt-4"
              >
                <!-- File Input -->
                <div class="mb-4">
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 text-left mb-2">
                    File
                  </label>
                  <div class="flex items-center gap-2">
                    <.live_file_input
                      upload={@uploads.audio}
                      class="block w-full text-sm text-gray-500 dark:text-gray-400
                             file:mr-4 file:py-2 file:px-4
                             file:rounded-md file:border-0
                             file:text-sm file:font-semibold
                             file:bg-blue-50 file:text-blue-700
                             dark:file:bg-blue-900 dark:file:text-blue-300
                             hover:file:bg-blue-100 dark:hover:file:bg-blue-800"
                    />
                  </div>
                  <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                    MP3, WAV, OGG or M4A up to 25MB
                  </p>
                  <%= for entry <- @uploads.audio.entries do %>
                    <div class="mt-2 text-sm text-blue-600 dark:text-blue-400">
                      {entry.client_name} ({format_bytes(entry.client_size)})
                    </div>
                  <% end %>
                  <%= if @upload_error do %>
                    <div class="mt-2 text-sm text-red-600 dark:text-red-400">
                      {@upload_error}
                    </div>
                  <% end %>
                </div>
                
    <!-- Name -->
                <div class="mb-4">
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 text-left">
                    Name
                  </label>
                  <input
                    type="text"
                    name="name"
                    autocomplete="off"
                    value={@upload_name}
                    placeholder="Sound name"
                    class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm
                           dark:bg-gray-700 dark:text-gray-100 dark:placeholder-gray-400"
                  />
                </div>
                
    <!-- Tags -->
                <div class="text-left">
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Tags
                  </label>
                  <div class="mt-2 flex flex-wrap gap-2">
                    <%= for tag <- @upload_tags do %>
                      <span class="inline-flex items-center gap-1 rounded-full bg-blue-50 dark:bg-blue-900 px-2 py-1 text-xs font-semibold text-blue-600 dark:text-blue-300">
                        {tag.name}
                        <button
                          type="button"
                          phx-click="remove_upload_tag"
                          phx-value-tag={tag.name}
                          class="text-blue-600 dark:text-blue-300 hover:text-blue-500 dark:hover:text-blue-200"
                        >
                          <svg class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                            <path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" />
                          </svg>
                        </button>
                      </span>
                    <% end %>
                  </div>
                  
    <!-- Tag Input -->
                  <div class="mt-2 relative">
                    <div>
                      <input
                        type="text"
                        value={@upload_tag_input}
                        phx-keyup="upload_tag_input"
                        phx-keydown="add_upload_tag"
                        phx-value-value={@upload_tag_input}
                        class="block w-full rounded-md border-gray-300 dark:border-gray-600 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm
                               dark:bg-gray-700 dark:text-gray-100 dark:placeholder-gray-400"
                        placeholder="Type a tag and press Enter or Tab..."
                        autocomplete="off"
                        id="upload-tag-input"
                        onkeydown="
                          if(event.key === 'Enter' || event.key === 'Tab') {
                            event.preventDefault();
                            const value = this.value;
                            requestAnimationFrame(() => this.value = '');
                            return false;
                          }
                        "
                      />
                    </div>

                    <%= if @upload_tag_input != "" and @upload_tag_suggestions != [] do %>
                      <div class="absolute z-10 mt-1 w-full bg-white dark:bg-gray-700 shadow-lg max-h-60 rounded-md py-1 text-base overflow-auto focus:outline-none sm:text-sm">
                        <%= for tag <- @upload_tag_suggestions do %>
                          <button
                            type="button"
                            phx-click="select_upload_tag"
                            phx-value-tag={tag.name}
                            class="w-full text-left px-4 py-2 text-sm hover:bg-blue-50 dark:hover:bg-blue-900 dark:text-gray-100"
                          >
                            {tag.name}
                          </button>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
                
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
                    class="inline-flex w-full justify-center rounded-md bg-blue-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600 dark:focus-visible:outline-offset-gray-800"
                    disabled={@uploads.audio.entries == [] || @upload_error}
                  >
                    Upload Sound
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
