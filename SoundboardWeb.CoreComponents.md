# `SoundboardWeb.CoreComponents`

The flash notices and icons every page uses, and the JS commands that show
and hide them. Icons are [heroicons](https://heroicons.com), bundled into
app.css by the Tailwind plugin.

# `flash`

Renders a flash notice: the inner block if given, otherwise the flash
message of the given kind.

    <.flash kind={:info} flash={@flash} />
    <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>

## Attributes

* `id` (`:string`) - the container's id; `flash-<kind>` when not given. Defaults to `nil`.
* `flash` (`:map`) - the map of flash messages to display. Defaults to `%{}`.
* `title` (`:string`) - Defaults to `nil`.
* `kind` (`:atom`) - used for styling and flash lookup. Must be one of `:info`, or `:error`.
* Global attributes are accepted. the arbitrary HTML attributes to add to the flash container.
## Slots

* `inner_block` - the optional inner block that renders the flash message.

# `flash_group`

The info and error flashes, and the notices shown while the connection is
lost.

    <.flash_group flash={@flash} />

## Attributes

* `flash` (`:map`) (required) - the map of flash messages.
* `id` (`:string`) - the optional id of flash container. Defaults to `"flash-group"`.

# `hide`

# `icon`

Renders a heroicon by its class name, sized and coloured with classes.

    <.icon name="hero-x-mark-solid" />
    <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />

## Attributes

* `name` (`:string`) (required)
* `class` (`:string`) - Defaults to `nil`.

# `show`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
