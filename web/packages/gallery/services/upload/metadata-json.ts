import { ensureElectron } from "ente-base/electron";
import { nameAndExtension } from "ente-base/file-name";
import log from "ente-base/log";
import type { Location } from "ente-base/types";
import {
    extractRawExif,
    parseExif,
    type RawExifTags,
} from "ente-gallery/services/exif";
import type {
    UploadItem,
    UploadPathPrefix,
} from "ente-gallery/services/upload";
import { readStream } from "ente-gallery/utils/native-stream";
import type { ParsedMetadataDate } from "ente-media/file-metadata";

export interface ParsedMetadataJSON {
    creationTime?: number;
    creationDate?: ParsedMetadataDate;
    modificationTime?: number;
    location?: Location;
    description?: string;
    favorited?: true;
    fromPartnerSharing?: true;
}

export const metadataJSONMapKeyForJSON = (
    pathPrefix: UploadPathPrefix | undefined,
    collectionID: number,
    jsonFileName: string,
) =>
    makeKey3(
        pathPrefix,
        collectionID,
        jsonFileName.slice(0, -1 * ".json".length),
    );

export const metadataJSONMapKeyForXMP = (
    pathPrefix: UploadPathPrefix | undefined,
    collectionID: number,
    xmpFileName: string,
) =>
    makeKey3(
        pathPrefix,
        collectionID,
        `${nameAndExtension(xmpFileName)[0]}.xmp`,
    );

const makeKey3 = (
    pathPrefix: UploadPathPrefix | undefined,
    collectionID: number,
    fileName: string,
) => `${pathPrefix ?? ""}-${collectionID}-${fileName}`;

export const matchJSONMetadata = (
    pathPrefix: UploadPathPrefix | undefined,
    collectionID: number,
    fileName: string,
    parsedMetadataJSONMap: Map<string, ParsedMetadataJSON>,
): ParsedMetadataJSON | undefined => {
    let [name, extension] = nameAndExtension(fileName);
    if (extension) {
        extension = "." + extension;
    }

    const originalName = name;

    // Takeout moves a trailing "(n)" after any clipped metadata suffix.
    let numberedSuffix = "";
    const endsWithNumberedSuffixWithBrackets = /\(\d+\)$/.exec(name);
    if (endsWithNumberedSuffixWithBrackets) {
        name = name.slice(0, -1 * endsWithNumberedSuffixWithBrackets[0].length);
        numberedSuffix = endsWithNumberedSuffixWithBrackets[0];
    }

    // Edited files reuse the original file's sidecar.
    const editedFileSuffix = "-edited";
    if (name.endsWith(editedFileSuffix)) {
        name = name.slice(0, -1 * editedFileSuffix.length);
    }

    const makeKey = (fn: string) => makeKey3(pathPrefix, collectionID, fn);

    let baseFileName = `${name}${extension}`;
    let key = makeKey(`${baseFileName}${numberedSuffix}`);

    let takeoutMetadata = parsedMetadataJSONMap.get(key);
    if (takeoutMetadata) return takeoutMetadata;

    // Takeout clips sidecar base names to 46 characters.
    const maxGoogleFileNameLength = 46;
    key = makeKey(
        `${baseFileName.slice(0, maxGoogleFileNameLength)}${numberedSuffix}`,
    );

    takeoutMetadata = parsedMetadataJSONMap.get(key);
    if (takeoutMetadata) return takeoutMetadata;

    // Newer exports append this suffix, sometimes without clipping.
    const supplSuffix = ".supplemental-metadata";
    baseFileName = `${name}${extension}${supplSuffix}`;
    key = makeKey(
        `${baseFileName.slice(0, maxGoogleFileNameLength)}${numberedSuffix}`,
    );

    takeoutMetadata = parsedMetadataJSONMap.get(key);
    if (takeoutMetadata) return takeoutMetadata;

    // Some exports leave "(n)" before the extension.
    if (numberedSuffix) {
        const originalBaseFileName = `${originalName}${extension}${supplSuffix}`;
        key = makeKey(originalBaseFileName.slice(0, maxGoogleFileNameLength));
        takeoutMetadata = parsedMetadataJSONMap.get(key);
        if (takeoutMetadata) return takeoutMetadata;
    }

    // Prefer existing clipped matches before trying untruncated sidecars.
    key = makeKey(`${baseFileName}${numberedSuffix}`);
    takeoutMetadata = parsedMetadataJSONMap.get(key);
    if (takeoutMetadata) return takeoutMetadata;

    if (numberedSuffix) {
        key = makeKey(`${originalName}${extension}${supplSuffix}`);
        takeoutMetadata = parsedMetadataJSONMap.get(key);
        if (takeoutMetadata) return takeoutMetadata;
    }

    // XMP sidecars use a source-specific suffix.
    return parsedMetadataJSONMap.get(makeKey(`${originalName}.xmp`));
};

export const parseXMPSidecarTags = (
    tags: RawExifTags,
): ParsedMetadataJSON | undefined => {
    const { creationDate, description } = parseExif(tags);
    const parseCoordinate = (
        value: string | undefined,
        reference: string | undefined,
    ) => {
        const match = /^(\d+(?:\.\d+)?)(?:,(\d+(?:\.\d+)?))?([NSEW])?$/.exec(
            value ?? "",
        );
        if (!match) return undefined;

        const direction = match[3] ?? reference?.trim().toUpperCase();
        if (!direction || !/^[NSEW]$/.test(direction)) return undefined;

        const coordinate = Number(match[1]) + Number(match[2] ?? 0) / 60;
        return direction == "S" || direction == "W" ? -coordinate : coordinate;
    };
    const latitude = parseCoordinate(
        tags.xmp?.GPSLatitude?.description,
        tags.xmp?.GPSLatitudeRef?.description,
    );
    const longitude = parseCoordinate(
        tags.xmp?.GPSLongitude?.description,
        tags.xmp?.GPSLongitudeRef?.description,
    );
    const location =
        latitude != undefined && longitude != undefined
            ? { latitude, longitude }
            : undefined;

    if (!creationDate && !location && !description) return undefined;

    return {
        creationDate,
        creationTime: creationDate?.timestamp,
        location,
        description,
    };
};

export const tryParseTakeoutMetadataJSON = async (
    uploadItem: UploadItem,
): Promise<ParsedMetadataJSON | undefined> => {
    try {
        return parseMetadataJSONText(await uploadItemText(uploadItem));
    } catch (e) {
        log.error("Failed to parse takeout metadata JSON", e);
        return undefined;
    }
};

export const tryParseXMPSidecar = async (
    uploadItem: UploadItem,
): Promise<ParsedMetadataJSON | undefined> => {
    try {
        const text = normalizeXMPSidecarText(await uploadItemText(uploadItem));
        return parseXMPSidecarTags(await extractRawExif(new Blob([text])));
    } catch (e) {
        log.error("Failed to parse XMP sidecar", e);
        return undefined;
    }
};

const normalizeXMPSidecarText = (text: string) => {
    const source = text
        .replace(/^\uFEFF/, "")
        .trimStart()
        .replace(/^<\?xml\s+[^>]*\?>\s*/i, "");
    return source.startsWith("<?xpacket begin")
        ? source
        : `<?xpacket begin=""?>\n${source}`;
};

export const tryParseTakeoutAlbumNameMetadataJSON = async (
    uploadItem: UploadItem,
): Promise<string | undefined> => {
    try {
        return parseAlbumNameMetadataJSONText(await uploadItemText(uploadItem));
    } catch (e) {
        log.error("Failed to parse takeout album metadata JSON", e);
        return undefined;
    }
};

const uploadItemText = async (uploadItem: UploadItem) => {
    if (uploadItem instanceof File) {
        return await uploadItem.text();
    } else if (typeof uploadItem == "string") {
        return await ensureElectron().fs.readTextFile(uploadItem);
    } else if (Array.isArray(uploadItem)) {
        const { response } = await readStream(ensureElectron(), uploadItem);
        return await response.text();
    } else {
        return await uploadItem.file.text();
    }
};

const parseMetadataJSONText = (text: string) => {
    const metadataJSON_ = JSON.parse(text) as unknown;
    if (typeof metadataJSON_ != "object") return undefined;
    if (!metadataJSON_) return undefined;
    if (Array.isArray(metadataJSON_)) return undefined;

    const metadataJSON = metadataJSON_ as Record<string, unknown>;

    const parsedMetadataJSON: ParsedMetadataJSON = {};

    parsedMetadataJSON.creationTime =
        parseGTTimestamp(metadataJSON.photoTakenTime) ??
        parseGTTimestamp(metadataJSON.creationTime);

    parsedMetadataJSON.modificationTime = parseGTTimestamp(
        metadataJSON.modificationTime,
    );

    parsedMetadataJSON.location =
        parseGTLocation(metadataJSON.geoData) ??
        parseGTLocation(metadataJSON.geoDataExif);

    parsedMetadataJSON.description = parseGTNonEmptyString(
        metadataJSON.description,
    );

    if (metadataJSON.favorited === true) {
        parsedMetadataJSON.favorited = true;
    }

    const googlePhotosOrigin = metadataJSON.googlePhotosOrigin;
    if (
        googlePhotosOrigin &&
        typeof googlePhotosOrigin == "object" &&
        "fromPartnerSharing" in googlePhotosOrigin
    ) {
        parsedMetadataJSON.fromPartnerSharing = true;
    }

    return parsedMetadataJSON;
};

const parseAlbumNameMetadataJSONText = (text: string) => {
    const metadataJSON_ = JSON.parse(text) as unknown;
    if (typeof metadataJSON_ != "object") return undefined;
    if (!metadataJSON_) return undefined;
    if (Array.isArray(metadataJSON_)) return undefined;

    const metadataJSON = metadataJSON_ as Record<string, unknown>;
    return parseGTNonEmptyString(metadataJSON.title);
};

const parseGTTimestamp = (o: unknown): number | undefined => {
    if (o && typeof o == "object" && "timestamp" in o) {
        const ot = o.timestamp;
        let timestamp: number | undefined;
        if (typeof ot == "string") {
            timestamp = parseInt(ot, 10);
        } else if (typeof ot == "number") {
            // Google writes strings; Ente desktop 1.7.11 and earlier wrote
            // numbers.
            timestamp = Math.floor(ot);
        }
        if (timestamp && !Number.isNaN(timestamp)) {
            return timestamp * 1e6;
        }
    }
    return undefined;
};

const parseGTLocation = (o: unknown): Location | undefined => {
    if (
        o &&
        typeof o == "object" &&
        "latitude" in o &&
        typeof o.latitude == "number" &&
        "longitude" in o &&
        typeof o.longitude == "number"
    ) {
        const { latitude, longitude } = o;
        // Takeout uses (0, 0) for missing locations.
        if (latitude !== 0 || longitude !== 0) return { latitude, longitude };
    }
    return undefined;
};

const parseGTNonEmptyString = (o: unknown): string | undefined =>
    o && typeof o == "string" ? o : undefined;
