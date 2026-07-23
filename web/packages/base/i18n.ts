import { isDevBuild } from "ente-base/env";
import log from "ente-base/log";
import { includes } from "ente-utils/type-guards";
import { getUserLocales } from "get-user-locale";
import i18n from "i18next";
import resourcesToBackend from "i18next-resources-to-backend";
import { initReactI18next } from "react-i18next";

/**
 * List of all {@link SupportedLocale}s.
 *
 * Locales are combinations of a language code, and an optional region code.
 *
 * For example, "en", "en-US", "en-IN" (Indian English), "pt" (Portuguese),
 * "pt-BR" (Brazilian Portuguese).
 *
 * In our Crowdin Project, we have work-in-progress translations into more
 * languages than this. When a translation reaches a high enough coverage, say
 * 90%, then we manually add it to this list of supported languages.
 */
export const supportedLocales = [
    "en-US" /* English */,
    "fr-FR" /* French */,
    "de-DE" /* German */,
    "ca-ES" /* Catalan */,
    "zh-CN" /* Simplified Chinese */,
    "zh-TW" /* Traditional Chinese */,
    "nl-NL" /* Dutch */,
    "es-ES" /* Spanish */,
    "pt-PT" /* Portuguese */,
    "pt-BR" /* Portuguese, Brazilian */,
    "ru-RU" /* Russian */,
    "pl-PL" /* Polish */,
    "it-IT" /* Italian */,
    "lt-LT" /* Lithuanian */,
    "uk-UA" /* Ukrainian */,
    "ur-IN" /* Urdu, India */,
    "vi-VN" /* Vietnamese */,
    "ja-JP" /* Japanese */,
    "ar-SA" /* Arabic */,
    "tr-TR" /* Turkish */,
    "cs-CZ" /* Czech */,
    "el-GR" /* Greek */,
] as const;

/** The type of {@link supportedLocales}. */
export type SupportedLocale = (typeof supportedLocales)[number];

const defaultLocale: SupportedLocale = "en-US";

/**
 * Load translations and add custom formatters.
 *
 * Localization and related concerns (aka "internationalization", or "i18n") for
 * our apps is handled by i18n framework.
 *
 * In addition to the base i18next package, we use two of its plugins:
 *
 * - i18next-http-backend, for loading the JSON files containing the translations
 *   at runtime, and
 *
 * - react-i18next, which adds React specific APIs
 *
 * This function also adds our custom formatters. They can be used within the
 * translated strings by using `{{val, formatterName}}`. For more details, see
 * https://www.i18next.com/translation-function/formatting.
 *
 * Our custom formatters:
 *
 * - "date": Formats an epoch microsecond value into a string containing the
 *   year, month and day of the the date. For example, under "en-US" it'll
 *   produce a string like "July 19, 2024".
 */
export const setupI18n = async () => {
    const localeString = localStorage.getItem("locale") ?? undefined;
    const locale = closestSupportedLocale(localeString);

    // https://www.i18next.com/overview/api
    await i18n
        // i18next-resources-to-backend: Use webpack to bundle translation, but
        // still fetch them lazily using a dynamic import.
        //
        // The benefit of this is that, unlike the http backend that uses files
        // from the public folder, these JSON files are content hash named and
        // eminently cacheable.
        //
        // https://github.com/i18next/i18next-resources-to-backend
        .use(
            resourcesToBackend(
                (language: string, namespace: string) =>
                    import(`./locales/${language}/${namespace}.json`),
            ),
        )
        // react-i18next: React support
        // Pass the i18n instance to react-i18next.
        .use(initReactI18next)
        // Initialize i18next
        // Option docs: https://www.i18next.com/overview/configuration-options
        .init({
            debug: isDevBuild,
            // i18next calls it language, but it really is the locale
            lng: locale,
            // Tell i18next about the locales we support
            supportedLngs: supportedLocales,
            // Ask it to fetch only exact matches
            //
            // By default, if the lng was set to, say, en-GB, i18n would make
            // network requests for ["en-GB", "en", "dev"] (where dev is the
            // default fallback). By setting `load` to "currentOnly", we ask
            // i18next to only try and fetch "en-GB" (i.e. the exact match).
            load: "currentOnly",
            // Disallow empty strings as valid translations.
            //
            // This way, empty strings will fallback to `fallbackLng`
            returnEmptyString: false,
            // The language to use if translation for a particular key in the
            // current `lng` is not available.
            fallbackLng: defaultLocale,
            interpolation: {
                escapeValue: false, // not needed for react as it escapes by default
            },
            react: {
                useSuspense: false,
                // Allow the following tags (without any attributes) to be used
                // in translations. Such keys can then be rendered using the
                // Trans component, but without otherwise needing any other
                // input from our side.
                //
                // https://react.i18next.com/latest/trans-component
                transKeepBasicHtmlNodesFor: ["br", "p", "strong", "code"],
            },
        });

    // To use this in a translation, interpolate as `{{val, date}}`.
    i18n.services.formatter?.addCached("date", (locale) => {
        // The "long" dateStyle:
        //
        // - Includes: year (y), long-month (MMMM), day (d)
        // - English pattern examples: MMMM d, y ("September 14, 1999")
        //
        const formatter = Intl.DateTimeFormat(locale, { dateStyle: "long" });
        // Value is an epoch microsecond so that we can directly pass the
        // timestamps we get from our API responses. The formatter expects
        // milliseconds, so divide by 1000.
        //
        // See [Note: Remote timestamps are epoch microseconds].
        return (val) => formatter.format(val / 1000);
    });
};

/**
 * Return the closest / best matching {@link SupportedLocale}.
 *
 * It takes as input a {@link savedLocaleString}, which denotes the user's
 * explicitly chosen preference (which we then persist in local storage).
 * Subsequently, we use this to (usually literally) return the supported locale
 * that it represents.
 *
 * If {@link savedLocaleString} is `undefined`, it tries to deduce the closest
 * {@link SupportedLocale} that matches the browser's locale.
 */
const closestSupportedLocale = (
    savedLocaleString?: string,
): SupportedLocale => {
    const ss = savedLocaleString;
    if (ss && includes(supportedLocales, ss)) return ss;

    for (const ls of getUserLocales()) {
        // Exact match
        if (ls && includes(supportedLocales, ls)) return ls;

        // Language match
        if (ls.startsWith("en")) {
            return "en-US";
        } else if (ls.startsWith("fr")) {
            return "fr-FR";
        } else if (ls.startsWith("de")) {
            return "de-DE";
        } else if (ls.startsWith("ca")) {
            return "ca-ES";
        } else if (
            ls.startsWith("zh-Hant") ||
            ls.startsWith("zh-TW") ||
            ls.startsWith("zh-HK") ||
            ls.startsWith("zh-MO")
        ) {
            return "zh-TW";
        } else if (ls.startsWith("zh")) {
            return "zh-CN";
        } else if (ls.startsWith("nl")) {
            return "nl-NL";
        } else if (ls.startsWith("es")) {
            return "es-ES";
        } else if (ls.startsWith("pt-BR")) {
            // We'll never get here (it'd already be an exact match), just kept
            // to keep this list consistent.
            return "pt-BR";
        } else if (ls.startsWith("pt")) {
            return "pt-PT";
        } else if (ls.startsWith("ru")) {
            return "ru-RU";
        } else if (ls.startsWith("pl")) {
            return "pl-PL";
        } else if (ls.startsWith("it")) {
            return "it-IT";
        } else if (ls.startsWith("lt")) {
            return "lt-LT";
        } else if (ls.startsWith("uk")) {
            return "uk-UA";
        } else if (ls.startsWith("ur")) {
            return "ur-IN";
        } else if (ls.startsWith("vi")) {
            return "vi-VN";
        } else if (ls.startsWith("ja")) {
            return "ja-JP";
        } else if (ls.startsWith("ar")) {
            return "ar-SA";
        } else if (ls.startsWith("tr")) {
            return "tr-TR";
        } else if (ls.startsWith("cs")) {
            return "cs-CZ";
        } else if (ls.startsWith("el")) {
            return "el-GR";
        }
    }

    // Fallback
    return defaultLocale;
};

/**
 * Return the locale that is currently being used to show the app's UI.
 *
 * Note that this may be different from the user's locale. For example, the
 * browser might be set to en-GB, but since we don't support that specific
 * variant of English, this value will be (say) en-US.
 */
export const getLocaleInUse = (): SupportedLocale => {
    const locale = i18n.resolvedLanguage;
    if (locale && includes(supportedLocales, locale)) {
        return locale;
    } else {
        // This shouldn't have happened. Log an error to attract attention.
        log.error(
            `Expected the i18next locale to be one of the supported values, but instead found ${locale}`,
        );
        return defaultLocale;
    }
};

/**
 * Set the locale that should be used to show the app's UI.
 *
 * This updates both the i18next state, and also the corresponding user
 * preference that is stored in local storage.
 */
export const setLocaleInUse = async (locale: SupportedLocale) => {
    localStorage.setItem("locale", locale);
    return i18n.changeLanguage(locale);
};

let _numberFormat: Intl.NumberFormat | undefined;

/**
 * Lazily created, cached, instance of NumberFormat used by
 * {@link formattedNumber}.
 *
 * See: [Note: Changing locale causes a full reload].
 */
const numberFormat = () =>
    (_numberFormat ??= new Intl.NumberFormat(i18n.language));

/**
 * Return the given {@link value} formatted for the current language and locale.
 *
 * In most cases, when a number needs to be displayed, it can be formatted as
 * part of the surrounding string using the {{count, number}} interpolation.
 * However, in some rare cases, we need to format a standalone number. For such
 * scenarios, this function can be used.
 */
export const formattedNumber = (value: number) => numberFormat().format(value);

let _listJoinFormat: Intl.ListFormat | undefined;

/**
 * Lazily created, cached, instance of NumberFormat used by
 * {@link formattedListJoin}.
 *
 * See: [Note: Changing locale causes a full reload].
 */
const listJoinFormat = () =>
    (_listJoinFormat ??= new Intl.ListFormat(i18n.language, {
        style: "narrow",
    }));

/**
 * Return the given {@link items} joined together into a single string using an
 * locale specific "comma like" separator.
 *
 * Usually this will just use a comma (plus space) as the list item separator,
 * but depending on the locale it might use a different separator too.
 *
 * e.g. ["Foo", "Bar"] becomes "Foo, Bar" in "en-US" and  "Foo、Bar" in "zh".
 */
export const formattedListJoin = (value: string[]) =>
    listJoinFormat().format(value);

/**
 * A no-op marker for strings that, for various reasons, pending addition to the
 * translation dataset.
 *
 * This function does nothing, it just returns back the passed it string
 * verbatim. It is only kept as a way for us to keep track of strings which
 * we've not yet added to the list of strings that should be translated (e.g.
 * perhaps we're awaiting feedback on the copy).
 *
 * It is the sibling of the {@link t} function provided by i18next.
 *
 * See also: {@link ut}.
 */
export const pt = (s: string) => s;

/**
 * A no-op marker for strings that, for various reasons, are not translated.
 *
 * This function does nothing, it just returns back the passed it string
 * verbatim. It is only kept as a way for us to keep track of strings that are
 * not translated (and for some reason, are currently not meant to be), but
 * still are user visible.
 *
 * It is the sibling of the {@link t} function provided by i18next.
 *
 * See also: {@link pt}.
 */
export const ut = (s: string) => s;
