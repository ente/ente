/** @file Dealing with the JSON metadata sidecar files */

import type {
    UploadItem,
    UploadPathPrefix,
} from "@/public-album/upload/pipeline";
import { nameAndExtension } from "ente-base/file-name";
import log from "ente-base/log";
import type { Location } from "ente-base/types";

/**
 * The data we read from the JSON metadata sidecar files.
 *
 * The metadata JSON file format is similar to the JSON metadata sidecar format
 * produced by Google Takeout. This is so that the user can import their Google
 * Takeouts while preserving the metadata.
 *
 * During export the Ente app also writes out its own metadata in a similar and
 * compatible format so that the user can easily round trip (i.e. export their
 * data out of Ente, and import it back again). This also allows users to reuse
 * existing third party tools for working with the takeout format.
 */
export interface ParsedMetadataJSON {
    creationTime?: number;
    modificationTime?: number;
    location?: Location;
    description?: string;
}

/**
 * Derive a key for the given {@link jsonFileName} that should be used to index
 * into the {@link ParsedMetadataJSON} JSON map.
 *
 * @param pathPrefix The {@link UploadPathPrefix}, if available.
 *
 * @param collectionID The collection to which we're uploading.
 *
 * @param jsonFileName The file name for the JSON file.
 *
 * @returns A key suitable for indexing into the metadata JSON map.
 *
 * @see also {@link matchJSONMetadata}.
 */
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

/**
 * Return the matching entry, if any, from {@link parsedMetadataJSONMap} for the
 * {@link pathPrefix}, {@link collectionID} and {@link fileName} combination.
 *
 * This is the sibling of {@link metadataJSONMapKeyForJSON}, except for deriving
 * the filename key we might have to try a bunch of different variations, so
 * this does not return a single key but instead tries the combinations until it
 * finds an entry in the map, and returns the found entry instead of the key.
 *
 * In brief,
 *
 * - When inserting the metadata entry into {@link parsedMetadataJSONMap}, we
 *   use {@link metadataJSONMapKeyForJSON}.
 *
 * - When reading back the metadata entry from {@link parsedMetadataJSONMap}, we
 *   use {@link matchJSONMetadata}
 */
export const matchJSONMetadata = (
    pathPrefix: UploadPathPrefix | undefined,
    collectionID: number,
    fileName: string,
    parsedMetadataJSONMap: Map<string, ParsedMetadataJSON>,
) => {
    // Break the fileName down into its components.
    let [name, extension] = nameAndExtension(fileName);
    if (extension) {
        extension = "." + extension;
    }

    // Save the original name before any modifications for fallback lookups.
    const originalName = name;

    // Trim off a suffix like "(1)" from the name, remembering what we trimmed
    // since we need to add it back later.
    //
    // It needs to be handled separately because of the clipping (see below).
    // The numbered suffix (if present) is not clipped. It is added at the end
    // of the clipped ".supplemental-metadata" portion, instead of after the
    // original filename.
    //
    // For example, "IMG_1234(1).jpg" would have a metadata filename of either
    // "IMG_1234.jpg(1).json" or "IMG_1234.jpg.supplemental-metadata(1).json".
    // And if the filename is too long, it gets turned into something like
    // "IMG_1234.jpg.suppl(1).json".

    let numberedSuffix = "";
    const endsWithNumberedSuffixWithBrackets = /\(\d+\)$/.exec(name);
    if (endsWithNumberedSuffixWithBrackets) {
        name = name.slice(0, -1 * endsWithNumberedSuffixWithBrackets[0].length);
        numberedSuffix = endsWithNumberedSuffixWithBrackets[0];
    }

    // Removes the "-edited" suffix, if present, so that the edited file can be
    // associated to the original file's metadataJSON file as edited files don't
    // have their own metadata files.

    const editedFileSuffix = "-edited";
    if (name.endsWith(editedFileSuffix)) {
        name = name.slice(0, -1 * editedFileSuffix.length);
    }

    // Convenience function to vary only the file name component when
    // constructing a key. Delegates to `makeKey3`.
    const makeKey = (fn: string) => makeKey3(pathPrefix, collectionID, fn);

    // Derive a key from the collection name, file name and the suffix if any.
    let baseFileName = `${name}${extension}`;
    let key = makeKey(`${baseFileName}${numberedSuffix}`);

    let takeoutMetadata = parsedMetadataJSONMap.get(key);
    if (takeoutMetadata) return takeoutMetadata;

    // If the file name is greater than 46 characters, then Google Photos, with
    // its infinite storage, clips the file name. In such cases we need to use
    // the clipped file name to get the key.

    const maxGoogleFileNameLength = 46;
    key = makeKey(
        `${baseFileName.slice(0, maxGoogleFileNameLength)}${numberedSuffix}`,
    );

    takeoutMetadata = parsedMetadataJSONMap.get(key);
    if (takeoutMetadata) return takeoutMetadata;

    // Newer Takeout exports are attaching a ".supplemental-metadata" suffix to
    // the file name of the metadataJSON file, you know, just to cause havoc,
    // and then clipping the file name if it's too long (ending up with
    // filenames "very_long_file_name.jpg.supple.json").
    //
    // Note that If the original filename is longer than 46 characters, then the
    // ".supplemental-metadata" suffix gets completely removed during the
    // clipping, along with a portion of the original filename (as before).
    //
    // For example, if the original filename is 45 characters long, then
    // everything except for the "." from ".supplemental-metadata" will get
    // clipped. So the metadata file ends up with a filename like
    // "filename_that_is_45_chars_long.jpg..json".

    const supplSuffix = ".supplemental-metadata";
    baseFileName = `${name}${extension}${supplSuffix}`;
    key = makeKey(
        `${baseFileName.slice(0, maxGoogleFileNameLength)}${numberedSuffix}`,
    );

    takeoutMetadata = parsedMetadataJSONMap.get(key);
    if (takeoutMetadata) return takeoutMetadata;

    // Some Google Takeout exports keep the numbered suffix in its original
    // position instead of moving it to the end. For example, "skytree (2).jpg"
    // may have metadata in "skytree (2).jpg.supplemental-metadata.json" instead
    // of "skytree.jpg.supplemental-metadata(2).json". Try that pattern too.
    if (numberedSuffix) {
        const originalBaseFileName = `${originalName}${extension}${supplSuffix}`;
        key = makeKey(originalBaseFileName.slice(0, maxGoogleFileNameLength));
        takeoutMetadata = parsedMetadataJSONMap.get(key);
    }

    return takeoutMetadata;
};

/**
 * Try to parse the contents of a metadata JSON file from a Google Takeout.
 */
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
    // Ignore non objects.
    if (typeof metadataJSON_ != "object") return undefined;
    // Ignore null.
    if (!metadataJSON_) return undefined;
    // Ignore arrays.
    if (Array.isArray(metadataJSON_)) return undefined;

    // At this point, `metadataJSON_` is an `object`, but TypeScript won't let
    // me index it. The following is the simplest (but unsafe) way I could think
    // of for convincing TypeScript to allow me to index `metadataJSON` with
    // `string`s.
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

/**
 * Parse a nullish epoch seconds timestamp string from a field in a Google
 * Takeout JSON, converting it into epoch microseconds if it is found.
 *
 * Note that the metadata provided by Google does not include the time zone
 * where the photo was taken, it only has an epoch seconds value. There is an
 * associated formatted date value (e.g. "17 Feb 2021, 03:22:16 UTC") but that
 * seems to be in UTC and doesn't have the time zone either.
 */
const parseGTTimestamp = (o: unknown): number | undefined => {
    if (o && typeof o == "object" && "timestamp" in o) {
        const ot = o.timestamp;
        let timestamp: number | undefined;
        if (typeof ot == "string") {
            timestamp = parseInt(ot, 10);
        } else if (typeof ot == "number") {
            // Ente desktop 1.7.11 and earlier used to write out a number, which
            // is the correct datatype, but that makes it inconsistent with the
            // numbers-as-string that Google takeout writes.
            //
            // So now we write out strings, and read either.
            timestamp = Math.floor(ot);
        }
        if (timestamp && !Number.isNaN(timestamp)) {
            return timestamp * 1e6;
        }
    }
    return undefined;
};

/**
 * Parse a (latitude, longitude) location pair field in a Google Takeout JSON.
 *
 * Apparently Google puts in (0, 0) to indicate missing data, so this function
 * only returns a parsed result if both components are present and non-zero.
 */
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
        if (latitude !== 0 || longitude !== 0) return { latitude, longitude };
    }
    return undefined;
};

/**
 * Parse a string from a field in a Google Takeout JSON, treating empty strings
 * as undefined.
 */
const parseGTNonEmptyString = (o: unknown): string | undefined =>
    o && typeof o == "string" ? o : undefined;
