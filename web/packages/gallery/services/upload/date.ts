import { nameAndExtension } from "ente-base/file-name";
import log from "ente-base/log";

// These heuristics recover dates from screenshots and chat app exports.
export const tryParseEpochMicrosecondsFromFileName = (
    fileName: string,
): number | undefined => {
    try {
        return parseEpochMicrosecondsFromFileName(fileName);
    } catch (e) {
        log.error(`Could not extract date from file name ${fileName}`, e);
        return undefined;
    }
};

const parseEpochMicrosecondsFromFileName = (fileName: string) => {
    let date: Date | undefined;

    fileName = fileName.trim();

    if (fileName.startsWith("IMG-") || fileName.startsWith("VID-")) {
        // WhatsApp: IMG-20171218-WA0028.jpg
        const p = fileName.split("-");
        const dateString = p[1];
        if (dateString) {
            date = parseDateFromFusedDateString(dateString);
        }
    } else if (fileName.startsWith("Screenshot_")) {
        // Android: Screenshot_20181227-152914.jpg
        const dateString = fileName.replace("Screenshot_", "");
        date = parseDateFromFusedDateString(dateString);
    } else if (fileName.startsWith("signal-")) {
        // Signal Android and Desktop use different timestamp layouts.
        const p = fileName.split("-");
        if (p.length > 5) {
            const dateString = `${p[1]}${p[2]}${p[3]}-${p[4]}${p[5]}${p[6]}`;
            date = parseDateFromFusedDateString(dateString);
        } else if (p.length > 1) {
            const dateString = `${p[1]}${p[2] ?? ""}${p[3] ?? ""}-${p[4] ?? ""}`;
            date = parseDateFromFusedDateString(dateString);
        }
    }

    if (!date) {
        const [name] = nameAndExtension(fileName);

        if (name.endsWith("_iOS")) {
            // iOS exports can encode UTC as 20230427_145116000_iOS.jpg.
            const p = name.split("_");
            if (p.length == 3) {
                const dateString = `${p[0]}-${p[1]}`;
                date = parseDateFromFusedDateString(dateString);
            }
        }
    }

    if (!date) {
        date = parseDateFromDigitGroups(fileName);
    }

    if (!date || isNaN(date.getTime())) {
        return undefined;
    }

    const unixTime = date.getTime() * 1000;
    if (unixTime === Date.UTC(0, 0, 0, 0, 0, 0, 0) || unixTime === 0) {
        // Zero dates occur in real files as missing metadata.
        return undefined;
    } else if (unixTime > Date.now() * 1000) {
        // A future filename date is usually an unrelated number we matched.
        return undefined;
    } else {
        return unixTime;
    }
};

interface DateComponents {
    year: number;
    month: number;
    day: number;
    hour: number;
    minute: number;
    second: number;
}

const parseDateFromFusedDateString = (s: string) =>
    validateAndGetDateFromComponents({
        year: Number(s.slice(0, 4)),
        month: Number(s.slice(4, 6)) - 1,
        day: Number(s.slice(6, 8)),
        hour: Number(s.slice(9, 11)),
        minute: Number(s.slice(11, 13)),
        second: Number(s.slice(13, 15)),
    });

export const parseDateFromDigitGroups = (s: string) => {
    const [year, month, day, hour, minute, second] = s.match(/\d+/g) ?? [];

    // Also recognize fused YYYYMMDD-HHMMSS dates.
    if (year?.length == 8 && month?.length == 6) {
        return parseDateFromFusedDateString(year + "-" + month);
    }

    return validateAndGetDateFromComponents({
        year: Number(year),
        month: Number(month) - 1,
        day: Number(day),
        hour: Number(hour),
        minute: Number(minute),
        second: Number(second),
    });
};

const validateAndGetDateFromComponents = (components: DateComponents) => {
    let date = dateFromComponents(components);
    if (hasTimeValues(components) && !isTimePartValid(date, components)) {
        // Keep a valid date even when its time is invalid.
        date = dateFromComponents({
            ...components,
            hour: 0,
            minute: 0,
            second: 0,
        });
    }
    if (!isDatePartValid(date, components)) {
        return undefined;
    }
    if (
        date.getFullYear() < 1990 ||
        date.getFullYear() > new Date().getFullYear() + 1
    ) {
        return undefined;
    }
    return date;
};

const isDatePartValid = (date: Date, { year, month, day }: DateComponents) =>
    date.getFullYear() === year &&
    date.getMonth() === month &&
    date.getDate() === day;

const isTimePartValid = (
    date: Date,
    { hour, minute, second }: DateComponents,
) =>
    date.getHours() === hour &&
    date.getMinutes() === minute &&
    date.getSeconds() === second;

const dateFromComponents = (dateComponents: DateComponents) => {
    const { year, month, day, hour, minute, second } = dateComponents;
    if (hasTimeValues(dateComponents)) {
        return new Date(year, month, day, hour, minute, second);
    } else {
        return new Date(year, month, day);
    }
};

const hasTimeValues = ({ hour, minute, second }: DateComponents) =>
    !isNaN(hour) && !isNaN(minute) && !isNaN(second);
