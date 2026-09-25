import type { CSSProperties } from "react";

import type { EnteFile } from "ente-media/file";
import type {
    PublicMemoryFile,
    PublicMemoryShareFrame,
    PublicMemoryShareFrameCrop,
    PublicMemoryShareMetadata,
} from "../services/public-memory";

const LANE_CROP_REGULAR_PADDING = 0.4;
const LANE_CROP_MINIMUM_PADDING = 0.1;

export interface LaneCaptionModel {
    prefix?: string;
    suffix?: string;
    text: string;
    value?: number;
}

export interface LaneCardSlice {
    index: number;
    distance: number;
}

const sortLaneFrames = (frames: PublicMemoryShareFrame[]) =>
    [...frames].sort((a, b) => {
        const aPosition = a.position ?? Number.MAX_SAFE_INTEGER;
        const bPosition = b.position ?? Number.MAX_SAFE_INTEGER;
        return aPosition - bPosition;
    });

export const alignLaneFilesWithMetadata = (
    publicFiles: PublicMemoryFile[],
    frames: PublicMemoryShareFrame[],
) => {
    const framesByPosition = new Map<number, PublicMemoryShareFrame>();
    for (const frame of sortLaneFrames(frames)) {
        if (
            typeof frame.position === "number" &&
            frame.position >= 0 &&
            !framesByPosition.has(frame.position)
        ) {
            framesByPosition.set(frame.position, frame);
        }
    }

    const orderedFiles: EnteFile[] = [];
    const orderedFrames: (PublicMemoryShareFrame | undefined)[] = [];

    publicFiles.forEach(({ file, position }) => {
        orderedFiles.push(file);
        orderedFrames.push(framesByPosition.get(position));
    });

    return { files: orderedFiles, frames: orderedFrames };
};

const normalizeCalendarDate = (date: Date) =>
    new Date(date.getFullYear(), date.getMonth(), date.getDate());

const parseCalendarDate = (value: string): Date | undefined => {
    const trimmed = value.trim();
    if (!trimmed) {
        return undefined;
    }

    const dateOnlyMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(trimmed);
    if (dateOnlyMatch) {
        const [, year, month, day] = dateOnlyMatch;
        const parsed = new Date(Number(year), Number(month) - 1, Number(day));
        if (
            Number.isNaN(parsed.getTime()) ||
            parsed.getFullYear() !== Number(year) ||
            parsed.getMonth() !== Number(month) - 1 ||
            parsed.getDate() !== Number(day)
        ) {
            return undefined;
        }

        return parsed;
    }

    const parsed = new Date(trimmed);
    if (Number.isNaN(parsed.getTime())) {
        return undefined;
    }

    return normalizeCalendarDate(parsed);
};

const safeDateInYear = (date: Date, year: number) => {
    const daysInTargetMonth = new Date(year, date.getMonth() + 1, 0).getDate();
    const targetDay = Math.min(date.getDate(), daysInTargetMonth);
    return new Date(year, date.getMonth(), targetDay);
};

const completedYearsBetween = (start: Date, end: Date) => {
    const startDate = normalizeCalendarDate(start);
    const endDate = normalizeCalendarDate(end);
    if (endDate.getTime() < startDate.getTime()) {
        return 0;
    }

    let years = endDate.getFullYear() - startDate.getFullYear();
    if (
        endDate.getTime() <
        safeDateInYear(startDate, endDate.getFullYear()).getTime()
    ) {
        years -= 1;
    }

    return Math.max(0, years);
};

const laneCaptionValue = ({
    captionType,
    creationDate,
    birthDate,
}: {
    captionType: "age" | "yearsAgo";
    creationDate: Date;
    birthDate?: string;
}) => {
    if (captionType === "age" && birthDate) {
        const parsedBirthDate = parseCalendarDate(birthDate);
        if (parsedBirthDate) {
            return completedYearsBetween(parsedBirthDate, creationDate);
        }
    }

    return completedYearsBetween(creationDate, new Date());
};

export const getFileAspectRatio = (file: EnteFile): number | undefined => {
    const width = file.pubMagicMetadata?.data.w;
    const height = file.pubMagicMetadata?.data.h;
    if (
        typeof width === "number" &&
        width > 0 &&
        typeof height === "number" &&
        height > 0
    ) {
        return width / height;
    }
    return undefined;
};

const clampCropRect = (
    crop: PublicMemoryShareFrameCrop,
): PublicMemoryShareFrameCrop => {
    const x = Math.min(Math.max(crop.x, 0), 1);
    const y = Math.min(Math.max(crop.y, 0), 1);
    const width = Math.min(Math.max(crop.width, 0.00001), 1 - x);
    const height = Math.min(Math.max(crop.height, 0.00001), 1 - y);
    return { x, y, width, height };
};

const computePaddedLaneCrop = (
    faceBox: PublicMemoryShareFrameCrop,
): PublicMemoryShareFrameCrop => {
    const normalizedBox = clampCropRect(faceBox);
    const xCrop =
        normalizedBox.x - normalizedBox.width * LANE_CROP_REGULAR_PADDING;
    const xOvershoot = Math.abs(Math.min(0, xCrop)) / normalizedBox.width;
    const widthCrop =
        normalizedBox.width * (1 + 2 * LANE_CROP_REGULAR_PADDING) -
        2 *
            Math.min(
                xOvershoot,
                LANE_CROP_REGULAR_PADDING - LANE_CROP_MINIMUM_PADDING,
            ) *
            normalizedBox.width;

    const yCrop =
        normalizedBox.y - normalizedBox.height * LANE_CROP_REGULAR_PADDING;
    const yOvershoot = Math.abs(Math.min(0, yCrop)) / normalizedBox.height;
    const heightCrop =
        normalizedBox.height * (1 + 2 * LANE_CROP_REGULAR_PADDING) -
        2 *
            Math.min(
                yOvershoot,
                LANE_CROP_REGULAR_PADDING - LANE_CROP_MINIMUM_PADDING,
            ) *
            normalizedBox.height;

    return clampCropRect({
        x: xCrop,
        y: yCrop,
        width: widthCrop,
        height: heightCrop,
    });
};

export const resolveLaneCropRect = (
    frame?: PublicMemoryShareFrame,
): PublicMemoryShareFrameCrop | undefined => {
    if (!frame) return undefined;
    if (frame.crop) return clampCropRect(frame.crop);
    if (frame.faceBox) return computePaddedLaneCrop(frame.faceBox);
    return undefined;
};

export const computeMediaCropStyle = ({
    cropRect,
    mediaAspectRatio,
    containerAspectRatio,
}: {
    cropRect?: PublicMemoryShareFrameCrop;
    mediaAspectRatio?: number;
    containerAspectRatio?: number;
}): CSSProperties | undefined => {
    if (
        !cropRect ||
        typeof mediaAspectRatio !== "number" ||
        mediaAspectRatio <= 0 ||
        typeof containerAspectRatio !== "number" ||
        containerAspectRatio <= 0
    ) {
        return undefined;
    }

    const safeCrop = clampCropRect(cropRect);
    const scale = Math.max(
        containerAspectRatio / (safeCrop.width * mediaAspectRatio),
        1 / safeCrop.height,
    );
    const renderedWidthPercent =
        (scale * mediaAspectRatio * 100) / containerAspectRatio;
    const renderedHeightPercent = scale * 100;
    const centerX = safeCrop.x + safeCrop.width / 2;
    const centerY = safeCrop.y + safeCrop.height / 2;

    return {
        position: "absolute",
        width: `${renderedWidthPercent}%`,
        height: `${renderedHeightPercent}%`,
        maxWidth: "none",
        maxHeight: "none",
        left: `calc(50% - ${centerX * renderedWidthPercent}%)`,
        top: `calc(50% - ${centerY * renderedHeightPercent}%)`,
        objectFit: "fill",
    };
};

const getFrameCreationDate = (frame?: PublicMemoryShareFrame) => {
    if (typeof frame?.creationTime !== "number") {
        return undefined;
    }
    const date = new Date(frame.creationTime / 1000);
    return Number.isNaN(date.getTime()) ? undefined : date;
};

export const buildLaneCaptionModel = ({
    frame,
    metadata,
    fallbackLabel,
}: {
    frame?: PublicMemoryShareFrame;
    metadata?: PublicMemoryShareMetadata;
    fallbackLabel: string;
}): LaneCaptionModel => {
    const creationDate = getFrameCreationDate(frame);
    if (!creationDate) {
        return { text: fallbackLabel };
    }

    const personName = metadata?.personName?.trim() ?? "";
    const captionType =
        metadata?.captionType ?? (metadata?.birthDate ? "age" : "yearsAgo");
    const roundedValue = laneCaptionValue({
        captionType,
        creationDate,
        birthDate: metadata?.birthDate,
    });
    const prefix =
        captionType === "age" ? "" : personName ? `${personName} ` : "";
    const suffix =
        captionType === "age"
            ? ` year${roundedValue === 1 ? "" : "s"} old`
            : ` year${roundedValue === 1 ? "" : "s"} ago`;
    return {
        prefix,
        suffix,
        text: `${prefix}${roundedValue}${suffix}`,
        value: roundedValue,
    };
};

export const buildLaneTitle = ({
    memoryName,
    personName,
}: {
    memoryName: string;
    personName?: string;
}) => {
    const trimmedTitle = memoryName.trim();
    const trimmedPersonName = personName?.trim() ?? "";
    const baseTitle = trimmedTitle || "Memory lane";

    if (!trimmedPersonName) {
        if (baseTitle.toLowerCase().includes("memory lane")) {
            return baseTitle;
        }
        return `${baseTitle} memory lane`;
    }

    const possessiveName = trimmedPersonName.endsWith("s")
        ? `${trimmedPersonName}'`
        : `${trimmedPersonName}'s`;
    return `${possessiveName} memory lane`;
};

export const easeInOutCubic = (value: number) =>
    value < 0.5
        ? 4 * value * value * value
        : 1 - Math.pow(-2 * value + 2, 3) / 2;

export const lerp = (start: number, end: number, t: number) =>
    start + (end - start) * t;

export const getLaneStackSlices = (
    frameCount: number,
    stackProgress: number,
): LaneCardSlice[] => {
    const slices: LaneCardSlice[] = [];
    const clampedProgress = Math.min(
        Math.max(stackProgress, 0),
        frameCount - 1,
    );
    const startIndex = Math.max(0, Math.floor(clampedProgress) - 3);
    const endIndex = Math.min(frameCount - 1, Math.ceil(clampedProgress) + 4);

    for (let index = startIndex; index <= endIndex; index++) {
        const distance = index - clampedProgress;
        if (distance < -4.5 || distance > 5.5) {
            continue;
        }
        slices.push({ index, distance });
    }

    const futureSlices = slices
        .filter((slice) => slice.distance >= 0)
        .sort((a, b) => b.distance - a.distance);
    const presentAndPastSlices = slices
        .filter((slice) => slice.distance < 0)
        .sort((a, b) => a.distance - b.distance);

    return [...futureSlices, ...presentAndPastSlices];
};

export const calculateLaneScale = (distance: number) => {
    if (distance >= 0) {
        return Math.max(0.84, 1.0 - distance * 0.05);
    }
    return Math.min(Math.max(1.0 - Math.abs(distance) * 0.02, 0.82), 1.02);
};

export const calculateLaneBlur = (distance: number) => {
    if (distance <= 0) {
        return 0;
    }
    const effective = Math.max(0, distance - 0.15);
    return Math.min(20, (effective + 0.05) * 10);
};

export const calculateLaneRotation = (distance: number) => {
    if (distance <= 0) {
        return 0;
    }
    const clamped = Math.min(Math.max(distance, 0), 3);
    const falloff = Math.max(0.2, 1 - clamped * 0.18);
    return 0.035 * clamped * falloff;
};

export const calculateLaneOpacity = (distance: number) => {
    if (distance >= 0) {
        return Math.max(0.35, 1 - distance * 0.22);
    }
    const drop = Math.abs(distance);
    return Math.max(0, 1 - drop * 0.85);
};

export const calculateLaneOverlayOpacity = (distance: number) => {
    if (distance <= 0) {
        return 0;
    }
    const normalized = Math.min(Math.max(distance / 3, 0), 1);
    return 0.45 * (1 - Math.pow(1 - normalized, 3));
};

export const laneCardShadow = (distance: number) => {
    const baseOpacity = 0.55;
    if (distance > 0) {
        return `0 26px 38px -6px rgba(0, 0, 0, ${Math.max(0, baseOpacity - distance * 0.12)})`;
    }
    const dampening = Math.max(0.2, 1 - Math.abs(distance) * 0.25);
    return `0 24px 34px -12px rgba(0, 0, 0, ${baseOpacity * dampening})`;
};
