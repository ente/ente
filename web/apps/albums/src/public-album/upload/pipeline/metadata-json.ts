import type {
    UploadItem,
    UploadPathPrefix,
} from "@/public-album/upload/pipeline";
import { nameAndExtension } from "ente-base/file-name";
import log from "ente-base/log";
import type { Location } from "ente-base/types";

// Keep this compatible with both Takeout and Ente export sidecars.
export interface ParsedMetadataJSON {
    creationTime?: number;
    modificationTime?: number;
    location?: Location;
    description?: string;
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
) => {
    let [name, extension] = nameAndExtension(fileName);
    if (extension) {
        extension = "." + extension;
    }

    const originalName = name;

    // Takeout moves "(n)" after the metadata suffix.
    // It does not clip the numbered suffix.
    let numberedSuffix = "";
    const endsWithNumberedSuffixWithBrackets = /\(\d+\)$/.exec(name);
    if (endsWithNumberedSuffixWithBrackets) {
        name = name.slice(0, -1 * endsWithNumberedSuffixWithBrackets[0].length);
        numberedSuffix = endsWithNumberedSuffixWithBrackets[0];
    }

    // Edited files share the original file's sidecar.
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

    // Newer Takeout exports add this suffix before clipping.
    const supplSuffix = ".supplemental-metadata";
    baseFileName = `${name}${extension}${supplSuffix}`;
    key = makeKey(
        `${baseFileName.slice(0, maxGoogleFileNameLength)}${numberedSuffix}`,
    );

    takeoutMetadata = parsedMetadataJSONMap.get(key);
    if (takeoutMetadata) return takeoutMetadata;

    // Some exports leave "(n)" in its original position.
    if (numberedSuffix) {
        const originalBaseFileName = `${originalName}${extension}${supplSuffix}`;
        key = makeKey(originalBaseFileName.slice(0, maxGoogleFileNameLength));
        takeoutMetadata = parsedMetadataJSONMap.get(key);
    }

    return takeoutMetadata;
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

const uploadItemText = async (uploadItem: UploadItem) =>
    await uploadItem.text();

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

    return parsedMetadataJSON;
};

const parseGTTimestamp = (o: unknown): number | undefined => {
    if (o && typeof o == "object" && "timestamp" in o) {
        const ot = o.timestamp;
        let timestamp: number | undefined;
        if (typeof ot == "string") {
            timestamp = parseInt(ot, 10);
        } else if (typeof ot == "number") {
            // Older Ente exports used numbers; Takeout uses strings.
            timestamp = Math.floor(ot);
        }
        if (timestamp && !Number.isNaN(timestamp)) {
            // Takeout uses seconds; Ente uses microseconds.
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
