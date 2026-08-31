# `SoundboardWeb.CoreComponents`

Provides core UI components.

At first glance, this module may seem daunting, but its goal is to provide
core building blocks for your application, such as modals, tables, and
forms. The components consist mostly of markup and are well-documented
with doc strings and declarative assigns. You may customize and style
them in any way you want, based on your application growth and needs.

The default components use Tailwind CSS, a utility-first CSS framework.
See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
how to customize them or feel free to swap in another framework altogether.

Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.

# `back`

Renders a back navigation link.

## Examples

    <.back navigate={~p"/posts"}>Back to posts</.back>

## Attributes

* `navigate` (`:any`) (required)
## Slots

* `inner_block` (required)

# `button`

Renders a button.

## Examples

    <.button>Send!</.button>
    <.button phx-click="go" class="ml-2">Send!</.button>

## Attributes

* `type` (`:string`) - Defaults to `nil`.
* `class` (`:string`) - Defaults to `nil`.
* Global attributes are accepted. Supports all globals plus: `["disabled", "form", "name", "value"]`.
## Slots

* `inner_block` (required)

# `error`

Generates a generic error message.

## Slots

* `inner_block` (required)

# `flash`

Renders flash notices.

## Examples

    <.flash kind={:info} flash={@flash} />
    <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>

## Attributes

* `id` (`:string`) - the optional id of flash container.
* `flash` (`:map`) - the map of flash messages to display. Defaults to `%{}`.
* `title` (`:string`) - Defaults to `nil`.
* `kind` (`:atom`) - used for styling and flash lookup. Must be one of `:info`, or `:error`.
* Global attributes are accepted. the arbitrary HTML attributes to add to the flash container.
## Slots

* `inner_block` - the optional inner block that renders the flash message.

# `flash_group`

Shows the flash group with standard titles and content.

## Examples

    <.flash_group flash={@flash} />

## Attributes

* `flash` (`:map`) (required) - the map of flash messages.
* `id` (`:string`) - the optional id of flash container. Defaults to `"flash-group"`.

# `header`

Renders a header with title.

## Attributes

* `class` (`:string`) - Defaults to `nil`.
## Slots

* `inner_block` (required)
* `subtitle`
* `actions`

# `hide`

# `hide_modal`

# `icon`

Renders a [Heroicon](https://heroicons.com).

Heroicons come in three styles – outline, solid, and mini.
By default, the outline style is used, but solid and mini may
be applied by using the `-solid` and `-mini` suffix.

You can customize the size and colors of the icons by setting
width, height, and background color classes.

Icons are extracted from the `deps/heroicons` directory and bundled within
your compiled app.css by the plugin in your `assets/tailwind.config.js`.

## Examples

    <.icon name="hero-x-mark-solid" />
    <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />

## Attributes

* `name` (`:string`) (required)
* `class` (`:string`) - Defaults to `nil`.

# `input`

Renders an input with label and error messages.

A `Phoenix.HTML.FormField` may be passed as argument,
which is used to retrieve the input name, id, and values.
Otherwise all attributes may be passed explicitly.

## Types

This function accepts all HTML input types, considering that:

  * You may also set `type="select"` to render a `<select>` tag

  * `type="checkbox"` is used exclusively to render boolean values

  * For live file uploads, see `Phoenix.Component.live_file_input/1`

See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
for more information. Unsupported types, such as hidden and radio,
are best written directly in your templates.

## Examples

    <.input field={@form[:email]} type="email" />
    <.input name="my-input" errors={["oh no!"]} />

## Attributes

* `id` (`:any`) - Defaults to `nil`.
* `name` (`:any`)
* `label` (`:string`) - Defaults to `nil`.
* `value` (`:any`)
* `type` (`:string`) - Defaults to `"text"`. Must be one of `"checkbox"`, `"color"`, `"date"`, `"datetime-local"`, `"email"`, `"file"`, `"month"`, `"number"`, `"password"`, `"range"`, `"search"`, `"select"`, `"tel"`, `"text"`, `"textarea"`, `"time"`, `"url"`, or `"week"`.
* `field` (`Phoenix.HTML.FormField`) - a form field struct retrieved from the form, for example: @form[:email].
* `errors` (`:list`) - Defaults to `[]`.
* `checked` (`:boolean`) - the checked flag for checkbox inputs.
* `prompt` (`:string`) - the prompt for select inputs. Defaults to `nil`.
* `options` (`:list`) - the options to pass to Phoenix.HTML.Form.options_for_select/2.
* `multiple` (`:boolean`) - the multiple flag for select inputs. Defaults to `false`.
* Global attributes are accepted. Supports all globals plus: `["accept", "autocomplete", "capture", "cols", "disabled", "form", "list", "max", "maxlength", "min", "minlength", "multiple", "pattern", "placeholder", "readonly", "required", "rows", "size", "step"]`.

# `label`

Renders a label.

## Attributes

* `for` (`:string`) - Defaults to `nil`.
## Slots

* `inner_block` (required)

# `list`

Renders a data list.

## Examples

    <.list>
      <:item title="Title">{@post.title}</:item>
      <:item title="Views">{@post.views}</:item>
    </.list>

## Slots

* `item` (required) - Accepts attributes:

  * `title` (`:string`) (required)

# `modal`

Renders a modal.

## Examples

    <.modal id="confirm-modal">
      This is a modal.
    </.modal>

JS commands may be passed to the `:on_cancel` to configure
the closing/cancel event, for example:

    <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
      This is another modal.
    </.modal>

## Attributes

* `id` (`:string`) (required)
* `show` (`:boolean`) - Defaults to `false`.
* `on_cancel` (`Phoenix.LiveView.JS`) - Defaults to `%Phoenix.LiveView.JS{ops: []}`.
## Slots

* `inner_block` (required)

# `show`

# `show_modal`

# `simple_form`

Renders a simple form.

## Examples

    <.simple_form for={@form} phx-change="validate" phx-submit="save">
      <.input field={@form[:email]} label="Email"/>
      <.input field={@form[:username]} label="Username" />
      <:actions>
        <.button>Save</.button>
      </:actions>
    </.simple_form>

## Attributes

* `for` (`:any`) (required) - the data structure for the form.
* `as` (`:any`) - the server side parameter to collect all input under. Defaults to `nil`.
* Global attributes are accepted. the arbitrary HTML attributes to apply to the form tag. Supports all globals plus: `["autocomplete", "name", "rel", "action", "enctype", "method", "novalidate", "target", "multipart"]`.
## Slots

* `inner_block` (required)
* `actions` - the slot for form actions, such as a submit button.

# `table`

Renders a table with generic styling.

## Examples

    <.table id="users" rows={@users}>
      <:col :let={user} label="id">{user.id}</:col>
      <:col :let={user} label="username">{user.username}</:col>
    </.table>

## Attributes

* `id` (`:string`) (required)
* `rows` (`:list`) (required)
* `row_id` (`:any`) - the function for generating the row id. Defaults to `nil`.
* `row_click` (`:any`) - the function for handling phx-click on each row. Defaults to `nil`.
* `row_item` (`:any`) - the function for mapping each row before calling the :col and :action slots. Defaults to `&Function.identity/1`.
## Slots

* `col` (required) - Accepts attributes:

  * `label` (`:string`)
* `action` - the slot for showing user actions in the last table column.

# `translate_error`

Translates an error message using gettext.

# `translate_errors`

Translates the errors for a field from a keyword list of errors.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
