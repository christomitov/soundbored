# `SoundboardWeb.Gettext`

A module providing Internationalization with a gettext-based API.

By using [Gettext](https://hexdocs.pm/gettext), your module compiles translations
that you can use in your application. To use this Gettext backend module,
call `use Gettext` and pass it as an option:

    use Gettext, backend: SoundboardWeb.Gettext

    # Simple translation
    gettext("Here is the string to translate")

    # Plural translation
    ngettext("Here is the string to translate",
             "Here are the strings to translate",
             3)

    # Domain-based translation
    dgettext("errors", "Here is the error message to translate")

See the [Gettext Docs](https://hexdocs.pm/gettext) for detailed usage.

# `handle_missing_bindings`

# `handle_missing_plural_translation`

# `handle_missing_translation`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
