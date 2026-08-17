import { appendCollectionKeyToShareURL } from "ente-gallery/services/share";
import type { EnteFile } from "ente-media/file";
import { fileCreationTime } from "ente-media/file-metadata";

const shortMonths = [
    "",
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
];

const possibleSingleFileQuickLinkOffsets = [-12 * 60, 0, 14 * 60];

export const isPossibleSingleFileQuickLinkName = (
    name: string,
    creationTime: number,
) =>
    possibleSingleFileQuickLinkOffsets.some((offsetMinutes) => {
        const date = new Date(creationTime / 1000 + offsetMinutes * 60 * 1000);
        return (
            name ===
            `${shortMonths[date.getUTCMonth() + 1]} ${date.getUTCDate()}, ${date.getUTCFullYear()}`
        );
    });

// Keep date formatting in sync with mobile.
export const quickLinkDateRangeForCreationTimes = (
    firstCreationTime: number,
    secondCreationTime: number,
) => {
    const startTime = new Date(firstCreationTime / 1000);
    const endTime = new Date(secondCreationTime / 1000);

    if (startTime.getFullYear() != endTime.getFullYear()) {
        return `${shortMonths[startTime.getMonth() + 1]} ${startTime.getDate()}, ${startTime.getFullYear()} - ${shortMonths[endTime.getMonth() + 1]} ${endTime.getDate()}, ${endTime.getFullYear()}`;
    }
    if (startTime.getMonth() != endTime.getMonth()) {
        return `${shortMonths[startTime.getMonth() + 1]} ${startTime.getDate()} - ${shortMonths[endTime.getMonth() + 1]} ${endTime.getDate()}, ${endTime.getFullYear()}`;
    }
    if (startTime.getDate() != endTime.getDate()) {
        return `${shortMonths[startTime.getMonth() + 1]} ${startTime.getDate()} - ${shortMonths[endTime.getMonth() + 1]} ${endTime.getDate()}, ${endTime.getFullYear()}`;
    }
    return `${shortMonths[endTime.getMonth() + 1]} ${endTime.getDate()}, ${endTime.getFullYear()}`;
};

export const quickLinkDateRangeForFiles = (files: EnteFile[]) => {
    if (!files.length) return undefined;

    let minCreationTime = Number.POSITIVE_INFINITY;
    let maxCreationTime = Number.NEGATIVE_INFINITY;
    for (const file of files) {
        const creationTime = fileCreationTime(file);
        if (creationTime < minCreationTime) minCreationTime = creationTime;
        if (creationTime > maxCreationTime) maxCreationTime = creationTime;
    }

    return quickLinkDateRangeForCreationTimes(minCreationTime, maxCreationTime);
};

export const quickLinkNameForFiles = (files: EnteFile[]) =>
    quickLinkDateRangeForFiles(files) ?? "Quick link";

const substituteCustomDomainIfNeeded = (
    url: string,
    customDomain: string | undefined,
) => {
    if (!customDomain) return url;
    const u = new URL(url);
    u.host = customDomain;
    return u.href;
};

export const resolveQuickLinkURL = async (
    publicURL: string,
    collectionKey: string,
    customDomain: string | undefined,
) =>
    substituteCustomDomainIfNeeded(
        await appendCollectionKeyToShareURL(publicURL, collectionKey),
        customDomain,
    );
