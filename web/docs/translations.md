# Ente web translations

The user-facing strings and translations shared by the web apps live in `packages/base/locales`. The apps load them with `i18next`.

## Translate

The strings can be translated in the [Ente Web Crowdin project](https://crowdin.com/project/ente-photos-web).

If your language is not listed, [request it on GitHub](https://github.com/ente/ente/issues/new?title=Request+for+New+Language+Translation&body=Language+name%3A+%0AProject%3A+web).

Partial translations are welcome; the apps generally enable a language after roughly 90% of its strings are translated.

## Add a string

1. Add the key and English text to [`translation.json`](../packages/base/locales/en-US/translation.json).

2. Use the key in the app code:

    ```ts
    import { t } from "i18next";

    t("new_string_key");
    ```

3. Commit the source string and app changes.

After the pull request merges, the [Crowdin workflow](../../.github/workflows/web-crowdin-sync.yml) uploads the new string. The same workflow downloads translations every Monday and opens a pull request for them.

## Update a string

> [!WARNING]
>
> Updating the English text invalidates its existing translations.

Update the value in [`translation.json`](../packages/base/locales/en-US/translation.json) and commit the change. After the pull request merges, the Crowdin workflow updates the source string.

## Delete a string

Remove every use of the key, remove it from [`translation.json`](../packages/base/locales/en-US/translation.json), and commit both changes. After the pull request merges, the Crowdin workflow removes the source string; its next translation pull removes the key from the translated files.
