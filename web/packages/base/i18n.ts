import { isDevBuild } from "ente-base/env";
import log from "ente-base/log";
import { includes } from "ente-utils/type-guards";
import { getUserLocales } from "get-user-locale";
import i18n from "i18next";
import resourcesToBackend from "i18next-resources-to-backend";
import { initReactI18next } from "react-i18next";

// Enable locales only after their Crowdin translations reach roughly 90%.
export const supportedLocales = [
    "ca-ES",
    "cs-CZ",
    "en-US",
    "es-ES",
    "de-DE",
    "fr-FR",
    "it-IT",
    "ja-JP",
    "nl-NL",
    "pl-PL",
    "pt-BR",
    "pt-PT",
    "ru-RU",
    "tr-TR",
    "uk-UA",
    "vi-VN",
    "zh-CN",
    "zh-TW",
    "lt-LT",
    "ur-IN",
    "ar-SA",
    "el-GR",
] as const;

export type SupportedLocale = (typeof supportedLocales)[number];

const defaultLocale: SupportedLocale = "en-US";

export const setupI18n = async () => {
    const localeString = localStorage.getItem("locale") ?? undefined;
    const locale = closestSupportedLocale(localeString);

    await i18n
        .use(
            resourcesToBackend(
                (language: string, namespace: string) =>
                    import(`./locales/${language}/${namespace}.json`),
            ),
        )
        .use(initReactI18next)
        .init({
            debug: isDevBuild,
            lng: locale,
            supportedLngs: supportedLocales,
            load: "currentOnly",
            returnEmptyString: false,
            fallbackLng: defaultLocale,
            interpolation: {
                escapeValue: false, // React escapes interpolated values.
            },
            react: {
                useSuspense: false,
                transKeepBasicHtmlNodesFor: ["br", "p", "strong", "code"],
            },
        });

    i18n.services.formatter?.addCached("date", (locale) => {
        const formatter = Intl.DateTimeFormat(locale, { dateStyle: "long" });
        // API timestamps are microseconds; DateTimeFormat expects milliseconds.
        return (val) => formatter.format(val / 1000);
    });
};

const closestSupportedLocale = (
    savedLocaleString?: string,
): SupportedLocale => {
    const ss = savedLocaleString;
    if (ss && includes(supportedLocales, ss)) return ss;

    for (const ls of getUserLocales()) {
        if (ls && includes(supportedLocales, ls)) return ls;

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

    return defaultLocale;
};

export const getLocaleInUse = (): SupportedLocale => {
    const locale = i18n.resolvedLanguage;
    if (locale && includes(supportedLocales, locale)) {
        return locale;
    } else {
        log.error(
            `Expected the i18next locale to be one of the supported values, but instead found ${locale}`,
        );
        return defaultLocale;
    }
};

export const setLocaleInUse = async (locale: SupportedLocale) => {
    localStorage.setItem("locale", locale);
    return i18n.changeLanguage(locale);
};

let _numberFormat: Intl.NumberFormat | undefined;

const numberFormat = () =>
    (_numberFormat ??= new Intl.NumberFormat(i18n.language));

export const formattedNumber = (value: number) => numberFormat().format(value);

let _listJoinFormat: Intl.ListFormat | undefined;

const listJoinFormat = () =>
    (_listJoinFormat ??= new Intl.ListFormat(i18n.language, {
        style: "narrow",
    }));

export const formattedListJoin = (value: string[]) =>
    listJoinFormat().format(value);

// Marks user-visible text pending translation.
export const pt = (s: string) => s;

// Marks intentionally untranslated text.
export const ut = (s: string) => s;
