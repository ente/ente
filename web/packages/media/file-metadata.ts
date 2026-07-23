import type { Location } from "ente-base/types";
import type { EnteFile } from "ente-media/file";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";
import { FileType } from "./file-type";

/**
 * Information about the file that never changes post upload.
 *
 * ---
 *
 * [Note: Metadatum]
 *
 * There are three different sources of metadata relating to a file.
 *
 * 1. Metadata
 * 2. Magic metadata
 * 3. Public magic metadata
 *
 * The names of API entities are such for historical reasons, but we can think
 * of them as:
 *
 * 1. Metadata
 * 2. Private mutable metadata
 * 3. Public mutable metadata
 *
 * Metadata is the original metadata that we attached to the file when it was
 * uploaded. It is immutable, and it never changes.
 *
 * Later on, the user might make changes to the file's metadata. Since the
 * metadata is immutable, we need a place to keep these mutations.
 *
 * Some mutations are "private" to the user who owns the file. For example, the
 * user might archive the file. Such modifications get written to (2), Private
 * Mutable Metadata.
 *
 * Other mutations are "public" across all the users with whom the file is
 * shared. For example, if the user (owner) edits the name of the file, all
 * people with whom this file is shared can see the new edited name. Such
 * modifications get written to (3), Shared Mutable Metadata.
 *
 * When the client needs to show a file, it needs to "merge" in two or three of
 * these sources (nb: remote will only send the permissible ones):
 *
 * - When showing a shared file, (1) and (3) are merged, with changes from (3)
 *   taking precedence, to obtain the full metadata pertinent to the file.
 *
 * - When showing a normal (un-shared) file, (1), (2) and (3) are merged, with
 *   changes from (2) and (3) taking precedence, to obtain the full metadata.
 *   (2) and (3) have no intersection of keys, so they can be merged in any
 *   order.
 *
 * While these sources can be conceptually merged, it is important for the
 * client to also retain the original sources unchanged. This is because the
 * metadatas (any of the three) might have keys that the current client does not
 * yet understand, so when updating some key, say filename in (3), it should
 * only edit the key it knows about but retain the rest of the source JSON
 * unchanged.
 *
 * A similar concept applies to collections, which can (like files) have
 * metadata associated with them with varying axis of mutability and access.
 *
 * Collections also have another type of metadata.
 *
 * 4. Shared magic metadata
 *
 * which in our hypothetical naming scheme can be thought of as
 *
 * 4. Per-sharee private mutable metadata
 *
 * This is "magic metadata" associated with each share. Each user with whom the
 * collection has been shared with can use it store metadata (e.g. archive
 * status) that is private to them, and can only be edited by them. For more
 * details on this type of metadata, see [Note: Share specific metadata].
 */
export interface FileMetadata {
    /**
     * The "Ente" file type - image, video or live photo.
     *
     * Expected to be one of {@link FileType}.
     *
     * See: [Note: Enums in remote objects] for why we keep it as a number
     * instead of the expected enum.
     */
    fileType: number;
    /**
     * The name of the file (including its extension).
     *
     * Don't use this property directly, use {@link fileFileName} instead which
     * takes into account subsequent edits too.
     */
    title: string;
    /**
     * The time when this file was created (epoch microseconds).
     *
     * This is our best attempt at detecting the time when the photo or live
     * photo or video was taken.
     *
     * - We first try to obtain this from metadata, using Exif and other
     *   metadata for images and FFmpeg-extracted metadata for video.
     *
     * - If no suitable metadata is available, then we try to deduce it from
     *   file name (e.g. for screenshots without any embedded metadata).
     *
     * - If nothing can be found, then it is set to the current time at the time
     *   of the upload.
     */
    creationTime: number;
    /**
     * The last modification time of the file (epoch microseconds).
     */
    modificationTime: number;
    /**
     * The latitude where the file was taken.
     */
    latitude?: number;
    /**
     * The longitude where the file was taken.
     */
    longitude?: number;
    /**
     * A hash of the file's contents.
     *
     * For images and videos this is the hash of the file's contents. For live
     * photos, this is the image hash joined with video hash using a colon (i.e.
     * `${imageHash}:{videoHash}`).
     *
     * Legacy compatibility:
     *
     * - The hash might not be present for files uploaded from ancient versions
     *   of Ente (Newer clients will always include it in the metadata).
     *
     * - For live photos, older version of the web and desktop client used to
     *   add two separate fields - {@link imageHash} and {@link videoHash} - to
     *   the file's metadata instead of setting the {@link hash}. This behaviour
     *   is deprecated, and if we now see a live photo without a {@link hash},
     *   we should reconstruct the hash locally from the image and video hashes
     *   by combining them as `${imageHash}:{videoHash}`.
     */
    hash?: string;
    /**
     * The hash of the image component of a live photo.
     *
     * This is a legacy field, and should not be added by us anymore. It is
     * retained to allow us to reconstruct the hash for live photos uploaded by
     * older clients.
     */
    imageHash?: string;
    /**
     * The hash of the video component of a live photo.
     *
     * This is a legacy field, and should not be added by us anymore. It is
     * retained to allow us to reconstruct the hash for live photos uploaded by
     * older clients.
     */
    videoHash?: string;
    /**
     * The duration (in integral seconds) of the video.
     *
     * Only present for videos (`fileType == FileType.video`). For compatibility
     * with other clients, this must be a integer number of seconds, without any
     * sub-second fraction.
     */
    duration?: number;
    /**
     * `true` if the uploading client was unable to generate a thumbnail for the
     * file when uploading it (e.g. unsupported format), and so instead a
     * placeholder thumbnail was used.
     */
    hasStaticThumbnail?: boolean;
}

/**
 * Zod schema for {@link FileMetadata}.
 */
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

/**
 * Mutable private metadata associated with an {@link EnteFile}.
 *
 * - Unlike {@link FileMetadata}, this can change after the file has been
 *   uploaded.
 *
 * - Unlike {@link PublicMagicMetadata}, this is only available to the owner of
 *   the file.
 *
 * [Note: Private magic metadata is called magic metadata on remote]
 *
 * For historical reasons, the unqualified phrase "magic metadata" in various
 * APIs refers to the (this) private metadata, even though the mutable public
 * metadata is the much more frequently used of the two. See: [Note: Metadatum].
 */
export interface FilePrivateMagicMetadataData {
    /**
     * The visibility of the file.
     *
     * The file's visibility is user specific attribute, and thus we keep it in
     * the private magic metadata. This allows the file's owner to share a file
     * and independently edit its visibility without revealing their visibility
     * preference to the other people with whom they have shared the file.
     *
     * Expected to be one of {@link ItemVisibility}.
     */
    visibility?: number;
}

/**
 * Zod schema for {@link FilePrivateMagicMetadataData}.
 *
 * See: [Note: Use looseObject for metadata Zod schemas]
 */
export const FilePrivateMagicMetadataData = z.looseObject({
    visibility: z.number().nullish().transform(nullToUndefined),
});

/**
 * The visibility of an Ente file or collection.
 */
export const ItemVisibility = {
    /**
     * The normal state - The item is visible.
     */
    visible: 0,
    /**
     * The item has been archived.
     */
    archived: 1,
    /**
     * The item has been hidden.
     */
    hidden: 2,
} as const;

/**
 * The visibility of an Ente file or collection.
 *
 * This is the erasable type. See the {@link ItemVisibility} object for the
 * possible values and their symbolic constants.
 */
export type ItemVisibility =
    (typeof ItemVisibility)[keyof typeof ItemVisibility];

/**
 * Mutable public metadata associated with an {@link EnteFile}.
 *
 * - Unlike {@link FileMetadata}, this can change after the file has been
 *   uploaded.
 *
 * - Unlike {@link FilePrivateMagicMetadataData}, this is available to all the
 *   people with whom the file has been shared.
 *
 * For more details, see [Note: Metadatum].
 *
 * ---
 *
 * [Note: Optional magic metadata keys]
 *
 * Remote does not support nullish (`undefined` or `null`) values for the keys
 * in the magic metadata associated with a file. All of the keys themselves are
 * optional though.
 *
 * That is, all magic metadata properties are of the form:
 *
 *     foo?: T
 *
 * And never like:
 *
 *     foo: T | undefined
 */
export interface FilePublicMagicMetadataData {
    /**
     * A ISO 8601 date time string without a timezone, indicating the local time
     * where the photo (or video) was taken.
     *
     * e.g. "2022-01-26T13:08:20".
     *
     * See: [Note: Photos are always in local date/time].
     */
    dateTime?: string;
    /**
     * When available, a "±HH:mm" string indicating the UTC offset of the place
     * where the photo was taken.
     *
     * e.g. "+02:00".
     */
    offsetTime?: string;
    /**
     * Modified value of the date time associated with an {@link EnteFile}.
     *
     * Epoch microseconds.
     *
     * This field stores edits to the {@link creationTime} {@link FileMetadata}
     * field.
     */
    editedTime?: number;
    /**
     * Modified file name of the {@link EnteFile}.
     *
     * This field stores edits to the {@link title} {@link FileMetadata} field.
     */
    editedName?: string;
    /**
     * The width of the photo (or video) in pixels.
     *
     * While this should usually be present, it is not guaranteed to be.
     */
    w?: number;
    /**
     * The height of the photo (or video) in pixels, if available.
     *
     * While this should usually be present, it is not guaranteed to be.
     */
    h?: number;
    /**
     * An arbitrary caption / description string that the user has added to the
     * file.
     *
     * The length of this field is capped to some arbitrary maximum by client
     * side checks.
     */
    caption?: string;
    /**
     * The name provided by the person who uploaded the file using an otherwise
     * anonymous public link upload.
     *
     * When sharing an album using a public link, the owner of the collection
     * can enable public uploads. When uploading files this way, the public
     * albums app asks the person doing the upload their name, and that gets
     * persisted here in the file's public magic metadata so that it can be
     * shown to the Ente users who are participants in the collection.
     *
     * (The owner of such files will be the owner of the collection)
     */
    uploaderName?: string;
    /** Camera make (manufacturer) extracted from metadata. */
    cameraMake?: string;
    /** Camera model extracted from metadata. */
    cameraModel?: string;
    /**
     * Edited latitude of the file
     *
     * If the user edits the location (latitude and longitude) of a file within
     * Ente, then the edits will be stored as the {@link lat} and {@link long}
     * properties in the file's public magic metadata.
     */
    lat?: number;
    /**
     * Edited longitude of the file.
     *
     * See {@link long}.
     */
    long?: number;
    /**
     * An arbitrary integer set to indicate that this file should be skipped for
     * the purpose of HLS generation.
     *
     * Current semantics:
     *
     * - if 1, skip this file
     * - otherwise attempt processing
     *
     * [Note: Marking files which do not need video processing]
     *
     * Some video files do not require generation of a HLS stream. The current
     * logic is H.264 files less than 10 MB, but this might change in future
     * clients.
     *
     * For such skipped files, there thus won't be a HLS playlist generated.
     * However, we still need a way to indicate to other clients that this file
     * has already been looked at.
     *
     * To that end, we add a flag to the public magic metadata for the file. To
     * allow future flexibility, this flag is an integer "streaming version".
     * Currently it is set to 1 by a client who recognizes that this file does
     * not need processing, and other clients can ignore this file if they find
     * sv == 1. In the future, there might be other values for sv (e.g. if the
     * skip logic changes).
     */
    sv?: number;
}

/**
 * Zod schema for the {@link PublicMagicMetadata} type.
 *
 * [Note: Use looseObject for metadata Zod schemas]
 *
 * It is important to (recursively) use the {@link looseObject} option when
 * defining Zod schemas for the various metadata types (the plaintext JSON
 * objects) because we want to retain all the fields we get from remote. There
 * might be other, newer, clients out there adding fields that the current
 * client might not we aware of, and we don't want to overwrite them.
 */
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

/**
 * Return the hash of the file by reading it from its metadata.
 *
 * This is a convenience function that directly reads the information from the
 * metadata in the happy path, but also has branches to handle the legacy format
 * that older clients used to upload. For more details, see the note in the
 * documentation for {@link hash} in {@link FileMetadata}.
 */
export const metadataHash = (metadata: FileMetadata) => {
    const hash = metadata.hash;
    if (hash) return hash;

    // Handle past live photos upload from web client.
    if (
        metadata.fileType == FileType.livePhoto &&
        metadata.imageHash &&
        metadata.videoHash
    ) {
        return `${metadata.imageHash}:${metadata.videoHash}`;
    }

    // Items uploaded by very old clients might not have a hash, so this is not
    // necessarily an error even if rare.
    return undefined;
};

/**
 * Return `true` if the {@link ItemVisibility} of the given {@link file} is
 * archived.
 */
export const isArchivedFile = (file: EnteFile) =>
    file.magicMetadata?.data.visibility == ItemVisibility.archived;

/**
 * Return the file name of the file (including both the name and the extension).
 *
 * This function handles files with edited names. It will first look into the
 * public magic metadata of a file to see if the file has an edited name, and if
 * so, return that. Otherwise it will return the original name of the file
 * stored in its metadata.
 *
 * @returns The provided {@link EnteFile}'s filename, including the extension.
 * e.g. "flower.png".
 */
export const fileFileName = (file: EnteFile) =>
    file.pubMagicMetadata?.data.editedName ?? file.metadata.title;

/**
 * Return the file's creation timestamp (epoch microseconds).
 *
 * This function handles files with edited dates.
 *
 * While sometimes the epoch timestamp is the correct value to use, it is also
 * possible that {@link fileCreationPhotoDate} or
 * {@link fileCreationPhotoSortTime} might be more appropriate.
 */
export const fileCreationTime = (file: EnteFile) =>
    file.pubMagicMetadata?.data.editedTime ?? file.metadata.creationTime;

/**
 * Return the file's creation date as a Date in the hypothetical "timezone of
 * the photo".
 *
 * This function handles files with edited dates. For all the details and
 * nuance, see {@link createPhotoDate}.
 */
export const fileCreationPhotoDate = (file: EnteFile) =>
    createPhotoDate(
        file.pubMagicMetadata?.data.dateTime ??
            file.pubMagicMetadata?.data.editedTime ??
            file.metadata.creationTime,
    );

/**
 * Return a millisecond sort key for the file's creation date in the
 * hypothetical "timezone of the photo".
 *
 * This is a photo-local comparable value, not an absolute UTC timestamp.
 */
export const fileCreationPhotoSortTime = (file: EnteFile) =>
    fileCreationPhotoDate(file).getTime();

/**
 * Return the GPS coordinates (if any) present in the given {@link EnteFile}.
 *
 * This function handles files with edited locations.
 */
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

/**
 * Return the camera make (manufacturer) for the file.
 */
export const fileCameraMake = (file: EnteFile): string | undefined => {
    const rawMake = file.pubMagicMetadata?.data.cameraMake;
    if (!rawMake) return undefined;
    const make = rawMake.trim();
    if (make.length === 0) return undefined;
    return make;
};

/**
 * Return the camera model for the file.
 */
export const fileCameraModel = (file: EnteFile): string | undefined => {
    const rawModel = file.pubMagicMetadata?.data.cameraModel;
    if (!rawModel) return undefined;
    const model = rawModel.trim();
    if (model.length === 0) return undefined;
    return model;
};

/**
 * Return a user-friendly string describing the camera used for the file.
 */
export const fileCameraLabel = (file: EnteFile): string | undefined => {
    const make = fileCameraMake(file);
    const model = fileCameraModel(file);
    if (!make && !model) return undefined;
    if (make && model) return `${make} ${model}`;
    return model ?? make;
};

/**
 * Return the duration of the video as a formatted "HH:mm:ss" string (when
 * present) for the given {@link EnteFile}.
 *
 * Only files with type `FileType.video` are expected to have a duration.
 *
 * @returns The duration of the video as a string of the form "HH:mm:ss". The
 * underlying duration present in the file's metadata is guaranteed to be
 * integral, so there will never be a subsecond component.
 *
 * - If the hour component is all zeroes, it will be omitted.
 *
 * - Leading zeros in the minutes component will be trimmed off if an hour
 *   component is not present. If minutes is all zeros, then "0" will be used.
 *
 * - For example, an underlying duration of 595 seconds will result in a
 *   formatted string of the form "9:55". While an underlying duration of 9
 *   seconds will be returned as a string "0:09".
 *
 * - A zero duration will be treated as undefined.
 */
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

/**
 * Metadata about a file extracted from various sources (like Exif) when
 * uploading it into Ente.
 *
 * Depending on the file type and the upload sequence, this data can come from
 * various places:
 *
 * - For images it comes from the Exif and other forms of metadata (XMP, IPTC)
 *   embedded in the file.
 *
 * - For videos, similarly it is extracted from the metadata embedded in the
 *   file using ffmpeg.
 *
 * - From various sidecar files (like metadata JSONs) that might be sitting next
 *   to the original during an import.
 *
 * These bits then get distributed and saved in the various metadata fields
 * associated with an {@link EnteFile} (See: [Note: Metadatum]).
 *
 * The advantage of having them be attached to an {@link EnteFile} is that it
 * allows us to perform operations using these attributes without needing to
 * re-download the original image.
 *
 * The disadvantage is that it increases the network payload (anything attached
 * to an {@link EnteFile} comes back in the diff response), and thus latency and
 * local storage costs for all clients. Thus, we need to curate what gets
 * preserved within the {@link EnteFile}'s metadatum.
 */
export interface ParsedMetadata {
    /** The width of the image, in pixels. */
    width?: number;
    /** The height of the image, in pixels. */
    height?: number;
    /**
     * The date/time when this photo was taken.
     *
     * Logically this is a date in local timezone of the place where the photo
     * was taken. See: [Note: Photos are always in local date/time].
     */
    creationDate?: ParsedMetadataDate | undefined;
    /** The GPS coordinates where the photo was taken. */
    location?: Location;
    /**
     * A caption / description attached by the user to the photo.
     */
    description?: string;
    /** Camera make (manufacturer) extracted from metadata (e.g. Apple, Canon). */
    cameraMake?: string;
    /** Camera model extracted from metadata (e.g. iPhone 15 Pro). */
    cameraModel?: string;
}

/**
 * [Note: Photos are always in local date/time]
 *
 * Photos out in the wild frequently do not have associated timezone offsets for
 * the date/time embedded in their metadata. This is a artifact of an era where
 * cameras didn't know often even know their date/time correctly, let alone the
 * UTC offset of their local data/time.
 *
 * This is beginning to change with smartphone cameras, and is even reflected in
 * the standards. e.g. Exif metadata now has auxiliary "OffsetTime*" tags for
 * indicating the UTC offset of the local date/time in the existing Exif tags
 * (See: [Note: Exif dates]).
 *
 * So a photos app needs to deal with a mixture of photos whose dates may or may
 * not have UTC offsets. This is fact #1.
 *
 * Users expect to see the time they took the photo, not the time in the place
 * they are currently. People expect a New Year's Eve photo from a vacation to
 * show up as midnight, not as (e.g.) 19:30 IST. This is fact #2.
 *
 * Combine these two facts, and if you ponder a bit, you'll find that there is
 * only one way for a photos app to show / sort / label the date – by using the
 * local date/time without the attached UTC offset, **even if it is present**.
 *
 * The UTC offset is still useful though, and we don't want to lose that
 * information. The number of photos with a UTC offset will only increase. And
 * whenever it is present, it provides additional context for the user.
 *
 * So we keep both the local date/time string (an ISO 8601 string guaranteed to
 * be without an associated UTC offset), and an (optional) UTC offset string.
 *
 * It is important to NOT think of the local date/time string as an instant of
 * time that can be converted to a UTC timestamp. It cannot be converted to a
 * UTC timestamp because while it itself might have the optional associated UTC
 * offset, its siblings photos might not. The only way to retain their
 * comparability is to treat them all the "time zone where the photo was taken".
 *
 * All this is good, but we still need to retain the existing `creationTime` UTC
 * epoch timestamp because in some cases when importing photos from other
 * providers, that's all we get. We could try and convert that to a date/time
 * string too, but since we anyways need to handle existing code that deals with
 * epoch timestamps, we retain them as they were provided.
 */
export interface ParsedMetadataDate {
    /**
     * A local date/time.
     *
     * This is a partial ISO 8601 date/time string guaranteed not to have a
     * timezone offset. e.g. "2023-08-23T18:03:00.000".
     */
    dateTime: string;
    /**
     * An optional offset from UTC.
     *
     * This is an optional UTC offset string of the form "±HH:mm" or "Z",
     * specifying the timezone offset for {@link dateTime} when available.
     */
    offset: string | undefined;
    /**
     * UTC epoch microseconds derived from {@link dateTime} and
     * {@link offset}.
     *
     * When the {@link offset} is present, this will accurately reflect a
     * UTC timestamp. When the {@link offset} is not present it convert to a
     * UTC timestamp by assuming that the given {@link dateTime} is in the local
     * time where this code is running. This is a good assumption but not always
     * correct (e.g. vacation photos).
     */
    timestamp: number;
}

/**
 * Parse a partial or full ISO 8601 string into a {@link ParsedMetadataDate}.
 *
 * @param s A partial or full ISO 8601 string. That is, it is a string of the
 * form "2023-08-23T18:03:00.000+05:30" or "2023-08-23T12:33:00.000Z" with all
 * components except the year potentially missing.
 *
 * @return A {@link ParsedMetadataDate}, or `undefined` if {@link s} cannot be
 * parsed.
 *
 * ---
 * Some examples:
 *
 * - "2023"                          => ("2023-01-01T00:00:00.000", undefined)
 * - "2023-08"                       => ("2023-08-01T00:00:00.000", undefined)
 * - "2023-08-23"                    => ("2023-08-23T00:00:00.000", undefined)
 * - "2023-08-23T18:03:00"           => ("2023-08-23T18:03:00.000", undefined)
 * - "2023-08-23T18:03:00+05:30"     => ("2023-08-23T18:03:00.000', "+05:30")
 * - "2023-08-23T18:03:00.000+05:30" => ("2023-08-23T18:03:00.000", "+05:30")
 * - "2023-08-23T12:33:00.000Z"      => ("2023-08-23T12:33:00.000", "Z")
 */
export const parseMetadataDate = (
    s: string,
): ParsedMetadataDate | undefined => {
    // Construct the timestamp using the original string itself. If s is
    // parseable as a date, then this'll be give us the correct UTC timestamp.
    // If the UTC offset is not present, then this will be in the local
    // (current) time.
    const timestamp = new Date(s).getTime() * 1000;
    if (isNaN(timestamp)) {
        // s in not a well formed ISO 8601 date time string.
        return undefined;
    }

    // Now we try to massage s into two parts - the local date/time string, and
    // an UTC offset string.

    let offset: string | undefined;
    let sWithoutOffset: string;

    // Check to see if there is a time-zone descriptor of the form "Z" or
    // "±05:30" or "±0530" at the end of s.
    const m = /Z|[+-]\d\d:?\d\d$/.exec(s);
    if (m?.index) {
        sWithoutOffset = s.substring(0, m.index);
        offset = s.substring(m.index);
    } else {
        sWithoutOffset = s;
    }

    // Convert sWithoutOffset - a potentially partial ISO 8601 string - to a
    // canonical ISO 8601 string.
    //
    // In its full generality, this is non-trivial. The approach we take is:
    //
    // 1. Rely on the browser to be able to partial ISO 8601 string. This relies
    //    on non-standard behaviour but works in practice seemingly.
    //
    // 2. Get an ISO 8601 representation of it. This is standard.
    //
    // A thing to watch out for is that browsers treat date only and date time
    // strings differently when the offset is not present (as would be for us).
    //
    // > When the time zone offset is absent, date-only forms are interpreted as
    // > a UTC time and date-time forms are interpreted as local time.
    // >
    // > https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date#date_time_string_format
    //
    // For our purpose, we want to always interpret them as UTC time. This way,
    // when we later gets back its string representation for step 2, we will get
    // back the same numerical value, and can just chop off the "Z".
    //
    // So if the length of the string is less than or equal to yyyy-mm-dd (10),
    // then we use it verbatim, otherwise we append a "Z".

    const date = new Date(
        sWithoutOffset + (sWithoutOffset.length <= 10 ? "" : "Z"),
    );

    // The string returned by `toISOString` is guaranteed to be UTC and denoted
    // by the suffix "Z". If we chop that off, we get back a canonical
    // representation we wish for: A otherwise well-formed ISO 9601 string but
    // any time zone descriptor.
    const dateTime = dropLast(date.toISOString());

    return { dateTime, offset, timestamp };
};

const dropLast = (s: string) => (s ? s.substring(0, s.length - 1) : s);

/**
 * Return a date that can be used on the represent a photo on the UI, by
 * constructing it from a {@link ParsedMetadataDate}, or its {@link dateTime}
 * component, or a UTC epoch timestamp.
 *
 * These dates are all hypothetically in the timezone of the place where the
 * photo was taken. Different photos might've been taken in different timezones,
 * which is why it is hypothetical, so concretely these are all mapped to the
 * current timezone.
 *
 * The difference is subtle, but we should not think of these as absolute points
 * on the UTC timeline. They are instead better thought of as dates without an
 * associated timezone. For the purpose of mapping them all to a comparable
 * dimension them we all contingently use the current timezone - this makes it
 * easy to use JavaScript Date constructor which assumes that any date/time
 * string without an associated timezone is in the current timezone.
 *
 * Whenever we're surfacing them in the UI, or using them for grouping (say by
 * day), we should use their current timezone representation, not the UTC one.
 *
 * See also: [Note: Photos are always in local date/time].
 */
export const createPhotoDate = (
    dateLike: ParsedMetadataDate | string | number,
) => {
    switch (typeof dateLike) {
        case "object":
            // A ISO 8601 string without a timezone. The Date constructor will
            // assume the timezone to be the current timezone.
            return new Date(dateLike.dateTime);
        case "string":
            // This is expected to be a string with the same meaning as
            // `ParsedMetadataDate.dateTime`.
            return new Date(dateLike);
        case "number":
            // A UTC epoch microseconds value.
            return new Date(dateLike / 1000);
    }
};
