const MICROSECONDS_IN_MILLISECOND = 1000;
const MICROSECONDS_IN_DAY = 24 * 60 * 60 * 1_000_000;
const BYTES_IN_GB = 1024 ** 3;
const BYTES_IN_MB = 1024 ** 2;

export const SUCCESS_COLOR = "#00B33C";

export const dateFromMicroseconds = (microseconds: number) =>
    new Date(microseconds / MICROSECONDS_IN_MILLISECOND);

export const dateToMicroseconds = (date: Date) =>
    date.getTime() * MICROSECONDS_IN_MILLISECOND;

export const microsecondsFromNow = (days: number) =>
    Date.now() * MICROSECONDS_IN_MILLISECOND + days * MICROSECONDS_IN_DAY;

export const bytesToGB = (bytes: number) => bytes / BYTES_IN_GB;

export const gbToBytes = (gb: number) => gb * BYTES_IN_GB;

export const formatBytesToGB = (bytes: number): string =>
    `${bytesToGB(bytes).toFixed(2)} GB`;

export const formatStorageSize = (bytes: number | undefined) => {
    if (bytes === undefined) {
        return "None";
    }
    if (bytes >= BYTES_IN_GB) {
        return `${bytesToGB(bytes).toFixed(2)} GB`;
    }
    return `${(bytes / BYTES_IN_MB).toFixed(2)} MB`;
};
