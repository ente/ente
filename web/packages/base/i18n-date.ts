import i18n, { t } from "i18next";

// Created on first use, since this module can load before i18n is initialised.
const lazyDateTimeFormat = (options: Intl.DateTimeFormatOptions) => {
    let format: Intl.DateTimeFormat | undefined;
    return () => (format ??= new Intl.DateTimeFormat(i18n.language, options));
};

const dateFormat = lazyDateTimeFormat({
    weekday: "short",
    day: "numeric",
    month: "short",
    year: "numeric",
});

const dateWithoutWeekdayFormat = lazyDateTimeFormat({
    day: "numeric",
    month: "short",
    year: "numeric",
});

const dateWithoutYearFormat = lazyDateTimeFormat({
    weekday: "short",
    day: "numeric",
    month: "short",
});

const timeFormat = lazyDateTimeFormat({ timeStyle: "short" });

interface FormattedDateOptions {
    omitWeekdayWhenYearIncluded?: boolean;
}

export const formattedDate = (date: Date, options?: FormattedDateOptions) =>
    (isSameYear(date)
        ? dateWithoutYearFormat()
        : options?.omitWeekdayWhenYearIncluded
          ? dateWithoutWeekdayFormat()
          : dateFormat()
    ).format(date);

const isSameYear = (date: Date) =>
    new Date().getFullYear() === date.getFullYear();

export const formattedTime = (date: Date) => timeFormat().format(date);

export const formattedDateTime = (
    dateOrEpochMicroseconds: Date | number,
    options?: FormattedDateOptions,
) => _formattedDateTime(toDate(dateOrEpochMicroseconds), options);

const _formattedDateTime = (date: Date, options?: FormattedDateOptions) =>
    [formattedDate(date, options), t("at"), formattedTime(date)].join(" ");

const toDate = (dm: Date | number) =>
    typeof dm == "number" ? new Date(dm / 1000) : dm;

let _relativeTimeFormat: Intl.RelativeTimeFormat | undefined;

export const formattedDateRelative = (
    dateOrEpochMicroseconds: Date | number,
) => {
    const units: [Intl.RelativeTimeFormatUnit, number][] = [
        ["year", 24 * 60 * 60 * 1000 * 365],
        ["month", (24 * 60 * 60 * 1000 * 365) / 12],
        ["day", 24 * 60 * 60 * 1000],
        ["hour", 60 * 60 * 1000],
        ["minute", 60 * 1000],
        ["second", 1000],
    ];

    const date = toDate(dateOrEpochMicroseconds);

    const elapsed = date.getTime() - Date.now();
    const elapsedMagnitude = Math.abs(elapsed);

    const relativeTimeFormat = (_relativeTimeFormat ??=
        new Intl.RelativeTimeFormat(i18n.language, {
            localeMatcher: "best fit",
            numeric: "always",
            style: "short",
        }));

    for (const [u, d] of units) {
        if (elapsedMagnitude > d)
            return relativeTimeFormat.format(Math.round(elapsed / d), u);
    }

    return relativeTimeFormat.format(Math.round(elapsed / 1000), "second");
};
