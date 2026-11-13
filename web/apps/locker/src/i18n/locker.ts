import i18n from "i18next";
import { useEffect, useState } from "react";
import enUS from "../locales/en-US/translation.json";
import frFR from "../locales/fr-FR/translation.json";
import jaJP from "../locales/ja-JP/translation.json";

const lockerLocaleBundles = {
    "en-US": enUS,
    "fr-FR": frFR,
    "ja-JP": jaJP,
} as const;

type LockerLocale = keyof typeof lockerLocaleBundles;

const ensureLockerBundle = (locale: LockerLocale) => {
    i18n.addResourceBundle(
        locale,
        "translation",
        lockerLocaleBundles[locale],
        true,
        true,
    );
};

const setupLockerI18n = () => {
    ensureLockerBundle("en-US");

    const locale = i18n.language as LockerLocale;
    if (locale in lockerLocaleBundles && locale !== "en-US") {
        ensureLockerBundle(locale);
    }
};

export const useSetupLockerI18n = () => {
    const [isLockerI18nReady, setIsLockerI18nReady] = useState(false);

    useEffect(() => {
        setupLockerI18n();
        setIsLockerI18nReady(true);
    }, []);

    return isLockerI18nReady;
};
