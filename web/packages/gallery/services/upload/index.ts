import { basename, dirname } from "ente-base/file-name";
import log from "ente-base/log";
import { customAPIOrigin } from "ente-base/origins";
import type { ZipItem } from "ente-base/types/ipc";
import { exportMetadataDirectoryName } from "ente-gallery/export-dirs";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { tryParseTakeoutAlbumNameMetadataJSON } from "./metadata-json";
import type { ExternalParsedMetadata } from "./upload-service";

/**
 * Internal in-memory state shared by the functions in this module.
 *
 * This entire object will be reset on logout.
 */
class UploadState {
    /**
     * `true` if the workers should be disabled for uploads.
     */
    shouldDisableCFUploadProxy = false;
    /**
     * `true` if uploads should include checksum metadata.
     */
    checksumProtectedUploadsEnabled = false;
}

/** State shared by the functions in this module. See {@link UploadState}. */
let _state = new UploadState();

/**
 * Reset any internal state maintained by the module.
 *
 * This is primarily meant as a way for stateful apps (e.g. photos) to clear any
 * user specific state on logout.
 */
export const resetUploadState = () => {
    _state = new UploadState();
};

/**
 * An item to upload is one of the following:
 *
 * 1. [web | desktop] A file drag-and-dropped or selected by the user when we
 *    are running in a web browser. This is the {@link File} case. There is one
 *    special case when this can also happen when running in the context of our
 *    desktop app - when the user edits an existing image.
 *
 * 2. [desktop] A file drag-and-dropped or selected by the user when we are
 *    running in the context of our desktop app. In such cases, we also have the
 *    absolute path of the file in the user's local file system. This is the
 *    {@link FileAndPath} case.
 *
 * 3. [desktop] A file path programmatically requested by the desktop app. For
 *    example, we might be resuming a previously interrupted upload after an app
 *    restart (thus we no longer have access to the {@link File} from case 2).
 *    Or we could be uploading a file this is in one of the folders the user has
 *    asked us to watch for changes. This is the `string` case.
 *
 * 4. [desktop] A file within a zip file on the user's local file system. This
 *    too is only possible when we are running in the context of our desktop
 *    app. The user might have drag-and-dropped or selected a zip file, or it
 *    might be a zip file that they'd previously selected but we now are
 *    resuming an interrupted upload of. Either ways, what we have is a tuple
 *    containing the (path to zip file, and the name of an entry within that zip
 *    file). This is the {@link ZipItem} case.
 *
 * Case 1 is possible both when we're running in the web app and desktop app
 * (that said, usually it only happens for the web app; it'll only happen in
 * desktop in the special case when editing an image).
 *
 * Case 2, 3 and 4 are only possible when we're running in the desktop app.
 *
 * Also see: [Note: Reading a UploadItem].
 */
export type UploadItem = File | FileAndPath | string | ZipItem;

/**
 * When we are running in the context of our desktop app, we have access to the
 * absolute path of {@link File} objects. This convenience type clubs these two
 * bits of information, saving us the need to query the path again and again
 * using the {@link getPathForFile} method of {@link Electron}.
 */
export interface FileAndPath {
    file: File;
    path: string;
}

/**
 * The cases of {@link UploadItem} that apply when we're running in the context
 * of our desktop app, and the item that was uploaded has an associated file on
 * the user's file system with a known path.
 *
 * See also {@link TimestampedFileSystemUploadItem}.
 */
export type FileSystemUploadItem = Exclude<UploadItem, File>;

/**
 * A {@link FileSystemUploadItem} augmented with the last modified time of the
 * corresponding file on disk.
 *
 * By keeping the last modified time, we can use it as a test of whether or not
 * the file on disk was modified since it was uploaded. Such an ability is
 * useful for tasks where there can be a arbitrary delay between when the file
 * was uploaded and when the file gets processed.
 *
 * See {@link toTimestampedDesktopUploadItem} for converting a
 * {@link FileSystemUploadItem} into a {@link TimestampedFileSystemUploadItem}
 * when running in the context of the desktop app.
 */
export interface TimestampedFileSystemUploadItem {
    /**
     * Information about the file system file which was uploaded to Ente.
     */
    fsUploadItem: FileSystemUploadItem;
    /**
     * The last modified time (epoch milliseconds) of the file system file.
     */
    lastModifiedMs: number;
}

/**
 * An "path prefix"-like opaque string which can be used to disambiguate
 * distinct source {@link UploadItem}s with the same name that are meant to be
 * uploaded to the same destination Ente album.
 *
 * Th documentation of {@link UploadItem} describes the four cases that an
 * {@link UploadItem} can be. For each of these, we augment an
 * {@link UploadItem} with a prefix ("dirname") derived from its best "path":
 *
 * - Relative path or name in the case of web {@link File}s.
 *
 * - Absolute path in the case of desktop {@link File} or path or
 *   {@link FileAndPath}.
 *
 * - Path within the zip file for desktop {@link ZipItem}s.
 *
 * Thus, this path should not be treated as an address that can be used to
 * retrieve the upload item, but rather as extra context that can help us
 * distinguish between items by their relative or path prefix when their file
 * names are the same and they're being uploaded to the same album.
 *
 * Consider the following hierarchy:
 *
 *     Foo/2017/Album1/1.png
 *     Foo/2017/Album1/1.png.json
 *
 *     Foo/2020/Album1/1.png
 *     Foo/2020/Album1/1.png.json
 *
 * If user uploads `Foo`, irrespective of if they select the "root" or "parent"
 * option {@link CollectionMapping} option, when matching the takeout, only the
 * Ente album is considered. So it will be undefined which JSON will get used,
 * and both PNG files will get the same JSON, not their file system siblings.
 *
 * In such cases, the path prefix of the item being uploaded can act as extra
 * context that can help us disambiguate and pick the sibling. Note how we don't
 * need the path prefix to be absolute or relative or even addressable, we just
 * need it as extra context that can help us disambiguate two items with
 * otherwise the same name and that are destined for the same Ente album.
 *
 * So for our example, the path prefixes will be
 *
 *     Foo/2017/Album1/1.png          "Foo/2017/Album1"
 *     Foo/2017/Album1/1.png.json     "Foo/2017/Album1"
 *
 *     Foo/2020/Album1/1.png          "Foo/2020/Album1"
 *     Foo/2020/Album1/1.png.json     "Foo/2020/Album1"
 *
 * And can thus be used to associate the correct metadata JSON with the
 * corresponding {@link UploadItem}.
 *
 * As a special case, "/metadata" at the end of the path prefix is discarded.
 * This allows the metadata JSON written by export to be read back in during
 * uploads. See: [Note: Fold "metadata" directory into parent folder].
 */
export type UploadPathPrefix = string;

/**
 * Return the {@link UploadPathPrefix} for the given {@link pathOrName} of an
 * item being uploaded.
 */
export const uploadPathPrefix = (pathOrName: string) => {
    const folderPath = dirname(pathOrName);
    if (basename(folderPath) == exportMetadataDirectoryName) {
        return dirname(folderPath);
    }
    return folderPath;
};

export type UploadItemAndPath = [UploadItem, string];

/**
 * Build a lookup of album-level Takeout `metadata.json` files by their
 * containing folder path.
 *
 * This only indexes files named exactly `metadata.json`. If multiple entries
 * exist for the same folder, the first one in the upload list is retained.
 */
const takeoutAlbumMetadataJSONItemsByFolderPath = (
    uploadItemAndPaths: UploadItemAndPath[],
) => {
    const result = new Map<string, UploadItem>();
    for (const [uploadItem, path] of uploadItemAndPaths) {
        if (basename(path) == "metadata.json") {
            const folderPath = dirname(path);
            if (!result.has(folderPath)) result.set(folderPath, uploadItem);
        }
    }
    return result;
};

/**
 * Return the album-level Takeout `metadata.json` upload item for the given
 * folder path, if one was included in the upload list.
 *
 * The `folderPath` must match the metadata file's containing folder exactly.
 * The returned item is not parsed here; callers parse its `title` when they
 * need an album-name suggestion.
 */
export const takeoutAlbumMetadataJSONItemForFolder = (
    uploadItemAndPaths: UploadItemAndPath[],
    folderPath: string,
): UploadItem | undefined => {
    return takeoutAlbumMetadataJSONItemsByFolderPath(uploadItemAndPaths).get(
        folderPath,
    );
};

/**
 * Group files that are that have the same parent folder into collections.
 *
 * This is used to segregate the list of {@link UploadItemAndPath}s that we
 * obtain when an upload is initiated into per-collection groups when the user
 * chooses the "parent" {@link CollectionMapping} option.
 *
 * For example, if the user selects files have a directory structure like:
 *
 *               a
 *             / |  \
 *            b  j   c
 *           /|\    /  \
 *          e f g   h  i
 *
 * The files will grouped into 3 collections:
 *
 *     [
 *       a => [j],
 *       b => [e, f, g],
 *       c => [h, i]
 *     ]
 *
 * @param defaultFolderName Optional collection name to use for any rooted files
 * that do not have a parent folder. The function will throw if a default is not
 * provided and we encounter any such files without a parent.
 */
export const groupItemsBasedOnParentFolder = async (
    uploadItemAndPaths: UploadItemAndPath[],
    defaultFolderName: string | undefined,
) => {
    const result = new Map<string, UploadItemAndPath[]>();
    const collectionNameByFolderPath = new Map<string, string>();
    const albumMetadataJSONItemsByFolderPath =
        takeoutAlbumMetadataJSONItemsByFolderPath(uploadItemAndPaths);
    for (const [uploadItem, pathOrName] of uploadItemAndPaths) {
        let folderPath = dirname(pathOrName);
        let folderName = basename(folderPath);
        // [Note: Fold "metadata" directory into parent folder]
        //
        // If the parent folder of a file is "metadata" (the directory in which
        // the exported JSON files are written), then we consider it to be part
        // of the parent folder.
        //
        // e.g. for the file list
        //
        //    [a/x.png, a/metadata/x.png.json]
        //
        // we want both to be grouped into the collection "a". This is so that
        // we can cluster the metadata JSON files in the same collection as the
        // file it is for.
        if (folderName == exportMetadataDirectoryName) {
            folderPath = dirname(folderPath);
            folderName = basename(folderPath);
        }
        if (!folderName) {
            if (!defaultFolderName)
                throw Error(`Leaf file (without default): ${pathOrName}`);
            folderName = defaultFolderName;
        }

        let collectionName = collectionNameByFolderPath.get(folderPath);
        if (collectionName == undefined) {
            const albumMetadataJSON =
                albumMetadataJSONItemsByFolderPath.get(folderPath);
            const albumName = albumMetadataJSON
                ? await tryParseTakeoutAlbumNameMetadataJSON(albumMetadataJSON)
                : undefined;
            collectionName = albumName ?? folderName;
            collectionNameByFolderPath.set(folderPath, collectionName);
        }

        if (!result.has(collectionName)) result.set(collectionName, []);
        result.get(collectionName)!.push([uploadItem, pathOrName]);
    }
    return result;
};

export interface LivePhotoAssets {
    image: UploadItem;
    video: UploadItem;
}

/**
 * An upload item with both parts of a live photo clubbed together.
 *
 * See: [Note: Intermediate file types during upload].
 */
export interface ClusteredUploadItem {
    localID: number;
    collectionID: number;
    fileName: string;
    isLivePhoto: boolean;
    uploadItem?: UploadItem;
    pathPrefix: UploadPathPrefix | undefined;
    externalParsedMetadata?: ExternalParsedMetadata;
    // TODO: Tie this to the isLivePhoto flag using a discriminated union.
    livePhotoAssets?: LivePhotoAssets;
}

/**
 * The file that we hand off to the uploader. Essentially
 * {@link ClusteredUploadItem} with the {@link collection} attached to it.
 *
 * See: [Note: Intermediate file types during upload].
 */
export type UploadableUploadItem = ClusteredUploadItem & {
    collection: Collection;
};

/**
 * Result of {@link markUploadedAndObtainProcessableItem}; see the documentation
 * of that function for the meaning and cases of this type.
 */
export type ProcessableUploadItem = File | TimestampedFileSystemUploadItem;

/**
 * As the long name suggests, this function does a rather specific thing:
 *
 * - If we're running in the context of the web app, it will return the
 *   {@link File} object that best represents the newly uploaded item. For
 *   images and videos, this'll be the newly uploaded file itself. For live
 *   photos, this will be the {@link File} object for the image component of the
 *   live photo.
 *
 * - If we're running in the context of the desktop app, it will first mark the
 *   item as having been uploaded in the persistent pending upload list that the
 *   desktop app keeps (so that they can be resumed on restarts). After this,
 *   it'll try to convert the item to a {@link TimestampedFileSystemUploadItem}
 *   if possible, otherwise will return the web {@link File}. As with the web
 *   case, in case of live photos the image component will be used in these
 *   transformations.
 *
 * @param item An {@link ClusteredUploadItem} that was recently uploaded.
 */
export const markUploadedAndObtainProcessableItem = async (
    item: ClusteredUploadItem,
): Promise<ProcessableUploadItem> => {
    const electron = globalThis.electron;
    if (!electron) {
        const resultItem = item.isLivePhoto
            ? item.livePhotoAssets!.image
            : item.uploadItem;
        if (resultItem instanceof File) {
            return resultItem;
        } else {
            throw new Error(
                `Unexpected upload item of type "${typeof resultItem}"`,
            );
        }
    }

    const timestamped = async (
        item: FileSystemUploadItem,
        t: Promise<number>,
    ): Promise<TimestampedFileSystemUploadItem> => ({
        fsUploadItem: item,
        lastModifiedMs: await t,
    });

    if (item.isLivePhoto) {
        const [p0, p1] = [
            item.livePhotoAssets!.image,
            item.livePhotoAssets!.video,
        ];
        if (Array.isArray(p0) && Array.isArray(p1)) {
            return timestamped(p0, electron.markUploadedZipItem(p0, p1));
        } else if (typeof p0 == "string" && typeof p1 == "string") {
            return timestamped(p0, electron.markUploadedFile(p0, p1));
        } else if (
            typeof p0 == "object" &&
            "path" in p0 &&
            typeof p1 == "object" &&
            "path" in p1
        ) {
            return timestamped(p0, electron.markUploadedFile(p0.path, p1.path));
        } else {
            throw new Error(
                "Attempting to mark upload completion of unexpected desktop upload items",
            );
        }
    } else {
        const p = item.uploadItem!;
        if (Array.isArray(p)) {
            return timestamped(p, electron.markUploadedZipItem(p));
        } else if (typeof p == "string") {
            return timestamped(p, electron.markUploadedFile(p));
        } else if (typeof p == "object" && "path" in p) {
            return timestamped(p, electron.markUploadedFile(p.path));
        } else {
            return p;
        }
    }
};

/**
 * Convert an {@link TimestampedFileSystemUploadItem} item back into a
 * {@link FileSystemUploadItem} if the underlying file hasn't changed.
 *
 * While this functionality is not directly related to upload, this function is
 * kept here since it is in some sense the inverse of
 * {@link markUploadedAndObtainProcessableItem}.
 *
 * @param item A {@link TimestampedFileSystemUploadItem}.
 *
 * @param fsStatMtime A function that can be used to perform IPC and obtain the
 * last modified time from the node side.
 *
 * @returns If the last modified time of the file system file pointed to by the
 * given {@link item} is the same as what is recorded within the structure, then
 * return the wrapped {@link FileSystemUploadItem}, otherwise return
 * `undefined`.
 *
 * In case of any errors, also return `undefined`. This is because errors are
 * expected if the underlying file system file was, e.g. renamed or removed
 * between the time the file was uploaded and we got around to processing it.
 */
export const fileSystemUploadItemIfUnchanged = async (
    { fsUploadItem, lastModifiedMs }: TimestampedFileSystemUploadItem,
    fsStatMtime: (path: string) => Promise<number>,
): Promise<FileSystemUploadItem | undefined> => {
    let path: string;
    if (typeof fsUploadItem == "string") {
        path = fsUploadItem;
    } else if (Array.isArray(fsUploadItem)) {
        // The last modified time we recorded was of the zip file that contains
        // the entry.
        path = fsUploadItem[0];
    } else {
        path = fsUploadItem.path;
    }

    try {
        const mtimeMs = await fsStatMtime(path);
        if (mtimeMs != lastModifiedMs) {
            log.info(
                `Not using upload item for path '${path}' since modified times have changed`,
            );
            return undefined;
        }
        return fsUploadItem;
    } catch (e) {
        log.warn(`Could not determine modified time for path '${path}'`, e);
        return undefined;
    }
};

/**
 * For each of cases of {@link UploadItem} that apply when we're running in the
 * context of our desktop app, return a value that can be passed to
 * {@link Electron} functions over IPC.
 */
export const toPathOrZipEntry = (fsUploadItem: FileSystemUploadItem) =>
    typeof fsUploadItem == "string" || Array.isArray(fsUploadItem)
        ? fsUploadItem
        : fsUploadItem.path;

export type UploadPhase =
    | "preparing"
    | "readingMetadata"
    | "uploading"
    | "cancelling"
    | "done";

export type UploadResult =
    | { type: "unsupported" }
    | { type: "zeroSize" }
    | { type: "tooLarge" }
    | { type: "partnerShared" }
    | { type: "largerThanAvailableStorage" }
    | { type: "blocked" }
    | { type: "failed" }
    | { type: "alreadyUploaded"; file: EnteFile }
    | { type: "addedSymlink"; file: EnteFile }
    | { type: "uploadedWithStaticThumbnail"; file: EnteFile }
    | { type: "uploaded"; file: EnteFile };

/**
 * Return true to disable the upload of files via Cloudflare Workers.
 *
 * [Note: Faster uploads via workers]
 *
 * These workers were introduced as a way of make file uploads faster:
 * https://ente.com/blog/tech/making-uploads-faster/
 *
 * By default, that's the route we take. However, there are multiple reasons why
 * this might be disabled.
 *
 * 1. During development and when self-hosting it we disable them to directly
 *    upload to the S3-compatible URLs returned by the ente API.
 *
 * 2. In rare cases, the user might have trouble reaching Cloudflare's network
 *    from their ISP. In such cases, the user can locally turn this off via
 *    settings.
 *
 * 3. There is also the original global toggle that was added when this feature
 *    was introduced.
 *
 * This function returns the in-memory value. It is updated when #2 changes (if
 * we're running in a context where that makes sense). The #3 remote status is
 * obtained once, on app start.
 */
export const shouldDisableCFUploadProxy = () =>
    _state.shouldDisableCFUploadProxy;

/**
 * Update the in-memory value of {@link shouldDisableCFUploadProxy}.
 *
 * @param savedPreference An optional user preference that the user has
 * expressed to disable the proxy.
 */
export const updateShouldDisableCFUploadProxy = async (
    savedPreference?: boolean,
) => {
    _state.shouldDisableCFUploadProxy =
        savedPreference || (await computeShouldDisableCFUploadProxy());
};

/**
 * Return `true` if uploads should include checksum metadata.
 */
export const areChecksumProtectedUploadsEnabled = () =>
    _state.checksumProtectedUploadsEnabled;

/**
 * Update the in-memory value controlling checksum protected uploads.
 */
export const updateChecksumProtectedUploadsEnabled = (enabled: boolean) => {
    _state.checksumProtectedUploadsEnabled = enabled;
};

const computeShouldDisableCFUploadProxy = async () => {
    // If a custom origin is set, that means we're not running a production
    // deployment (maybe we're running locally, or being self-hosted).
    //
    // In such cases, disable the Cloudflare upload proxy (which won't work for
    // self-hosters), and instead just directly use the upload URLs that museum
    // gives us.
    return !!(await customAPIOrigin());
};
