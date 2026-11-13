import { uniqueFilesByID } from "ente-gallery/utils/file";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";

export const slideshowDurationOptions = [5, 10, 15, 30, 60, 300, 600];

export interface SlideshowSettings {
    durationSeconds: number;
    randomOrder: boolean;
    blurredBackground: boolean;
}

export const savedSlideshowSettings = (): SlideshowSettings => {
    const durationSeconds = Number(
        localStorage.getItem("album_slideshow.duration_seconds"),
    );
    return {
        durationSeconds: slideshowDurationOptions.includes(durationSeconds)
            ? durationSeconds
            : 5,
        randomOrder:
            localStorage.getItem("album_slideshow.random_order") === "true",
        blurredBackground:
            localStorage.getItem("album_slideshow.blurred_background") !==
            "false",
    };
};

export const saveSlideshowSettings = (settings: SlideshowSettings) => {
    localStorage.setItem(
        "album_slideshow.duration_seconds",
        String(settings.durationSeconds),
    );
    localStorage.setItem(
        "album_slideshow.random_order",
        String(settings.randomOrder),
    );
    localStorage.setItem(
        "album_slideshow.blurred_background",
        String(settings.blurredBackground),
    );
};

export const slideshowFiles = (files: EnteFile[]) =>
    uniqueFilesByID(
        files.filter(
            ({ metadata: { fileType } }) =>
                fileType === FileType.image || fileType === FileType.livePhoto,
        ),
    );

export const slideshowIndex = (index: number, offset: number, count: number) =>
    count ? (index + offset + count) % count : 0;

export const slideshowPrefetchFiles = (
    files: EnteFile[],
    index: number,
    direction: number,
) => {
    if (files.length < 2) return [];
    const indexes = [1, 2, -1].map((offset) =>
        slideshowIndex(index, offset * direction, files.length),
    );
    return [...new Set(indexes)]
        .filter((nextIndex) => nextIndex !== index)
        .map((nextIndex) => files[nextIndex]!);
};

export function scheduleSlideshowAdvance(
    {
        enabled,
        ready,
        count,
        durationSeconds = 5,
    }: {
        enabled: boolean;
        ready: boolean;
        count: number;
        durationSeconds?: number;
    },
    advance: () => void,
) {
    const timer =
        enabled && count > 1
            ? setTimeout(advance, ready ? durationSeconds * 1000 : 10_000)
            : undefined;
    return () => clearTimeout(timer);
}
