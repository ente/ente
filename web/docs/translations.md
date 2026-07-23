# Translations

We use Crowdin for translations, and the `i18next` library to load these at runtime.

Within our project we have the _source_ strings - these are the key value pairs in the `packages/base/locales/en-US/translation.json` file.

Volunteers can add a new _translation_ in their language corresponding to each such source key-value to our [Crowdin project](https://crowdin.com/project/ente-photos-web).

Every Monday, and whenever source strings or the Crowdin config change on `main`, we run a [GitHub workflow](../../.github/workflows/web-crowdin-sync.yml) that

- Uploads sources to Crowdin - So any new key value pair we add in the source `translation.json` becomes available to translators to translate.

- Downloads translations from Crowdin - So any new translations that translators have made on the Crowdin dashboard (for existing sources) will be added to the corresponding `lang/translation.json`.

The workflow also uploads the current source strings before downloading translations.

## Adding a new string

- Add a new entry in `packages/base/locales/en-US/translation.json` (the **source `translation.json`**).
- Use the new key in code with the `t` function (`import { t } from "i18next"`).
- During the next sync, the workflow will upload this source item to Crowdin's dashboard, allowing translators to translate it.

## Updating an existing string

- Update the existing value for the key in the source `translation.json`.
- During the next sync, the workflow will clear out all the existing translations so that they can be translated afresh.

## Deleting an existing string

- Remove the key value pair from the source `translation.json`.
- During the next sync, the workflow will delete that source item from all existing translations (both in the Crowdin project and also from the other `lang/translation.json` files in the repository).
