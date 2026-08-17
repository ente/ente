import type { Location } from "ente-base/types";
import type { EnteFile } from "ente-media/file";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";
import { FileType } from "./file-type";

export interface FileMetadata {
    // One of FileType. Kept as a plain number so that parsing does not break
    // when remote adds new cases.
    fileType: number;
    // Use fileFileName instead of reading this directly; it also accounts for
    // subsequent edits.
    title: string;
    creationTime: number;
    modificationTime: number;
    latitude?: number;
    longitude?: number;
    // For live photos this is the image hash and the video hash joined by a
    // colon, i.e. `${imageHash}:${videoHash}`.
    hash?: string;
    // imageHash and videoHash are legacy fields. Old clients set them for live
    // photos instead of hash; new clients must not add them.
    imageHash?: string;
    videoHash?: string;
    // Integral seconds. Other clients expect no sub-second fraction.
    duration?: number;
    hasStaticThumbnail?: boolean;
}

// looseObject, here and in the other metadata schemas, so that fields written
// by newer clients are retained instead of being dropped on the next write.
export const FileMetadata = z.looseObject({
    fileType: z.number(),
    title: z.string(),
    creationTime: z.number(),
    modificationTime: z.number(),
    latitude: z.number().nullish().transform(nullToUndefined),
    longitude: z.number().nullish().transform(nullToUndefined),
    hash: z.string().nullish().transform(nullToUndefined),
    imageHash: z.string().nullish().transform(nullToUndefined),
    videoHash: z.string().nullish().transform(nullToUndefined),
    duration: z.number().nullish().transform(nullToUndefined),
    hasStaticThumbnail: z.boolean().nullish().transform(nullToUndefined),
});

export interface FilePrivateMagicMetadataData {
    // One of ItemVisibility. Kept in the private metadata so that people with
    // whom the file is shared never see the owner's visibility preference.
    visibility?: number;
}

export const FilePrivateMagicMetadataData = z.looseObject({
    visibility: z.number().nullish().transform(nullToUndefined),
});

export const ItemVisibility = { visible: 0, archived: 1, hidden: 2 } as const;

export type ItemVisibility =
    (typeof ItemVisibility)[keyof typeof ItemVisibility];

export interface FilePublicMagicMetadataData {
    // An ISO 8601 date/time string without a timezone, in the local time of
    // the place where the photo was taken. e.g. "2022-01-26T13:08:20".
    dateTime?: string;
    // UTC offset of the place where the photo was taken. e.g. "+02:00".
    offsetTime?: string;
    editedTime?: number;
    editedName?: string;
    w?: number;
    h?: number;
    caption?: string;
    // The name given by an anonymous person who uploaded the file via a
    // public link. Such files are owned by the collection owner.
    uploaderName?: string;
    cameraMake?: string;
    cameraModel?: string;
    // lat and long are location edits made within Ente; they take precedence
    // over the latitude and longitude in FileMetadata.
    lat?: number;
    long?: number;
    // Streaming version. A client that decides a video does not need an HLS
    // stream sets this to 1, and other clients then skip processing it.
    sv?: number;
}

export const FilePublicMagicMetadataData = z.looseObject({
    dateTime: z.string().nullish().transform(nullToUndefined),
    offsetTime: z.string().nullish().transform(nullToUndefined),
    editedTime: z.number().nullish().transform(nullToUndefined),
    editedName: z.string().nullish().transform(nullToUndefined),
    w: z.number().nullish().transform(nullToUndefined),
    h: z.number().nullish().transform(nullToUndefined),
    // Some legacy remote records have been seen with numeric captions.
    caption: z
        .union([z.string(), z.number()])
        .nullish()
        .transform((v) => (v == null ? undefined : String(v))),
    uploaderName: z.string().nullish().transform(nullToUndefined),
    cameraMake: z.string().nullish().transform(nullToUndefined),
    cameraModel: z.string().nullish().transform(nullToUndefined),
    lat: z.number().nullish().transform(nullToUndefined),
    long: z.number().nullish().transform(nullToUndefined),
    sv: z.number().nullish().transform(nullToUndefined),
});

export const metadataHash = (metadata: FileMetadata) => {
    const hash = metadata.hash;
    if (hash) return hash;

    if (
        metadata.fileType == FileType.livePhoto &&
        metadata.imageHash &&
        metadata.videoHash
    ) {
        return `${metadata.imageHash}:${metadata.videoHash}`;
    }

    // Files uploaded by very old clients might not have a hash, so a missing
    // hash is not an error.
    return undefined;
};

export const isArchivedFile = (file: EnteFile) =>
    file.magicMetadata?.data.visibility == ItemVisibility.archived;

export const fileFileName = (file: EnteFile) =>
    file.pubMagicMetadata?.data.editedName ?? file.metadata.title;

export const fileCreationTime = (file: EnteFile) =>
    file.pubMagicMetadata?.data.editedTime ?? file.metadata.creationTime;

export const fileCreationPhotoDate = (file: EnteFile) =>
    createPhotoDate(
        file.pubMagicMetadata?.data.dateTime ??
            file.pubMagicMetadata?.data.editedTime ??
            file.metadata.creationTime,
    );

// The result is a comparable photo-local value in milliseconds, not an
// absolute UTC timestamp.
export const fileCreationPhotoSortTime = (file: EnteFile) =>
    fileCreationPhotoDate(file).getTime();

export const fileLocation = (file: EnteFile): Location | undefined => {
    const { lat, long } = file.pubMagicMetadata?.data ?? {};
    // Use (lat, long) only if both are present and nonzero.
    const edited = lat && long;

    const latitude = nullToUndefined(edited ? lat : file.metadata.latitude);
    const longitude = nullToUndefined(edited ? long : file.metadata.longitude);

    if (latitude === undefined || longitude === undefined) return undefined;
    if (Number.isNaN(latitude) || Number.isNaN(longitude)) return undefined;
    if (latitude === 0 && longitude === 0) return undefined;

    return { latitude, longitude };
};

export const fileCameraMake = (file: EnteFile): string | undefined => {
    const rawMake = file.pubMagicMetadata?.data.cameraMake;
    if (!rawMake) return undefined;
    const make = rawMake.trim();
    if (make.length === 0) return undefined;
    return make;
};

export const fileCameraModel = (file: EnteFile): string | undefined => {
    const rawModel = file.pubMagicMetadata?.data.cameraModel;
    if (!rawModel) return undefined;
    const model = rawModel.trim();
    if (model.length === 0) return undefined;
    return model;
};

export const fileCameraLabel = (file: EnteFile): string | undefined => {
    const make = fileCameraMake(file);
    const model = fileCameraModel(file);
    if (!make && !model) return undefined;
    if (make && model) return `${make} ${model}`;
    return model ?? make;
};

export const fileDurationString = (file: EnteFile): string | undefined => {
    const d = file.metadata.duration;
    if (!d) return undefined;

    const s = d % 60;
    const m = Math.floor(d / 60) % 60;
    const h = Math.floor(d / 3600);

    const ss = s > 9 ? `${s}` : `0${s}`;
    if (h) {
        const mm = m > 9 ? `${m}` : `0${m}`;
        return `${h}:${mm}:${ss}`;
    } else {
        return `${m}:${ss}`;
    }
};

export interface ParsedMetadata {
    width?: number;
    height?: number;
    creationTime?: number;
    creationDate?: ParsedMetadataDate | undefined;
    location?: Location;
    description?: string;
    cameraMake?: string;
    cameraModel?: string;
}

// Photo dates often have no UTC offset.
// Keep their wall-clock time local; offset is context, not display time.
export interface ParsedMetadataDate {
    // A partial ISO 8601 date/time string guaranteed not to have a timezone
    // offset. e.g. "2023-08-23T18:03:00.000".
    dateTime: string;
    // A UTC offset of the form "±HH:mm" or "Z", when available.
    offset: string | undefined;
    // Epoch microseconds. Without offset, this uses the current timezone.
    timestamp: number;
}

export const parseMetadataDate = (
    s: string,
): ParsedMetadataDate | undefined => {
    // Date uses the current timezone when s has no offset.
    const timestamp = new Date(s).getTime() * 1000;
    if (isNaN(timestamp)) return undefined;

    let offset: string | undefined;
    let sWithoutOffset: string;

    const m = /Z|[+-]\d\d:?\d\d$/.exec(s);
    if (m?.index) {
        sWithoutOffset = s.substring(0, m.index);
        offset = s.substring(m.index);
    } else {
        sWithoutOffset = s;
    }

    // Browsers parse date-only forms as UTC but date-time forms as local.
    // Force date-time forms through UTC so both canonicalize the same way.
    const date = new Date(
        sWithoutOffset + (sWithoutOffset.length <= 10 ? "" : "Z"),
    );

    const dateTime = dropLast(date.toISOString());

    return { dateTime, offset, timestamp };
};

const dropLast = (s: string) => (s ? s.substring(0, s.length - 1) : s);

export const createPhotoDate = (
    dateLike: ParsedMetadataDate | string | number,
) => {
    switch (typeof dateLike) {
        case "object":
            return new Date(dateLike.dateTime);
        case "string":
            return new Date(dateLike);
        case "number":
            // Epoch microseconds to milliseconds.
            return new Date(dateLike / 1000);
    }
};
