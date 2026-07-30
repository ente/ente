import i18n, { t } from "i18next";

/**
 * Return `true` if both the given dates have the same day.
 */
export const isSameDay = (first: Date, second: Date) =>
    first.getFullYear() === second.getFullYear() &&
    first.getMonth() === second.getMonth() &&
    first.getDate() === second.getDate();

const translatedRelativeTime = (
    key: "just_now" | "minutes_ago" | "hours_ago" | "days_ago",
    fallback: string,
    count?: number,
) => {
    const translated = t(key, count === undefined ? undefined : { count });
    return typeof translated != "string" || !translated || translated == key
        ? fallback
        : translated;
};

/**
 * Format a server timestamp in microseconds using the same thresholds as the
 * comments sidebar: relative labels for recent comments, locale dates for older
 * ones.
 */
export const formatTimeAgo = (timestampMicros: number): string => {
    const timestampMs = Math.floor(timestampMicros / 1000);
    const now = Date.now();
    const diff = now - timestampMs;
    const minutes = Math.floor(diff / 60000);
    if (minutes < 1) return translatedRelativeTime("just_now", "just now");
    if (minutes < 60) {
        return translatedRelativeTime(
            "minutes_ago",
            `${minutes}m ago`,
            minutes,
        );
    }
    const hours = Math.floor(minutes / 60);
    if (hours < 24) {
        return translatedRelativeTime("hours_ago", `${hours}h ago`, hours);
    }
    const days = Math.floor(hours / 24);
    if (days < 7) {
        return translatedRelativeTime("days_ago", `${days}d ago`, days);
    }

    const date = new Date(timestampMs);
    const currentYear = new Date(now).getFullYear();
    const locale = i18n.language || "en-US";
    if (date.getFullYear() === currentYear) {
        return date.toLocaleDateString(locale, {
            month: "short",
            day: "numeric",
        });
    }
    return date.toLocaleDateString(locale, {
        month: "short",
        day: "numeric",
        year: "numeric",
    });
};
