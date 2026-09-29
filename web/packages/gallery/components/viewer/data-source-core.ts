import type { PublicAlbumsCredentials } from "ente-base/http";
import log from "ente-base/log";
import type { RenderableSourceURLs } from "ente-gallery/services/download-core";
import type { RawExifTags } from "ente-gallery/services/exif";
import type { EnteFile } from "ente-media/file";
import type { ParsedMetadata } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { ensureString } from "ente-utils/ensure";

interface PhotoSwipeSlideData {
    src?: string | undefined;
    width?: number | undefined;
    height?: number | undefined;
    alt?: string;
    html?: string | undefined;
}

export type ItemData = PhotoSwipeSlideData & {
    fileID: number;
    fileType: number;
    imageURL?: string;
    originalImageBlob?: Blob;
    videoURL?: string;
    videoPlaylistURL?: string;
    mediaControllerID?: string;
    isContentLoading?: boolean;
    isContentZoomable?: boolean;
    fetchFailed?: boolean;
    isTransient?: boolean;
};

interface FileInfoExif {
    tags: RawExifTags | undefined;
    parsed: ParsedMetadata | undefined;
}

interface HLSPlaylistData {
    playlistURL: string;
    width: number;
    height: number;
}

type HLSPlaylistDataForFile = HLSPlaylistData | "skip" | undefined;

export interface ItemDataOpts {
    videoQuality?: "auto" | "original";
}

interface FileViewerDataSourceDownloadManager {
    readonly publicAlbumsCredentials: PublicAlbumsCredentials | undefined;
    renderableThumbnailURL: (file: EnteFile) => Promise<string | undefined>;
    renderableSourceURLs: (file: EnteFile) => Promise<RenderableSourceURLs>;
}

export interface FileViewerDataSourceDeps {
    downloadManager: FileViewerDataSourceDownloadManager;
    hlsPlaylistDataForFile: (
        file: EnteFile,
        publicAlbumsCredentials?: PublicAlbumsCredentials,
    ) => Promise<HLSPlaylistDataForFile>;
    extractRawExif: (blob: Blob) => Promise<RawExifTags>;
    parseExif: (tags: RawExifTags) => ParsedMetadata;
}

export interface FileViewerDataSource {
    logoutFileViewerDataSource: () => void;
    resetFileViewerDataSourceOnClose: () => void;
    fileViewerWillOpen: () => void;
    fileViewerDidClose: () => void;
    itemDataForFile: (
        file: EnteFile,
        opts: ItemDataOpts | undefined,
        needsRefresh: () => void,
    ) => ItemData;
    forgetItemDataForFileID: (fileID: number) => void;
    forgetItemDataForFileIDIfNeeded: (fileID: number) => void;
    updateItemDataAlt: (fileID: number, newAlt: string) => void;
    fileInfoExifForFile: (
        file: EnteFile,
        observer: (exifData: FileInfoExif) => void,
    ) => FileInfoExif | undefined;
    updateFileInfoExifIfNeeded: (itemData: ItemData) => Promise<void>;
    forgetExifForItemData: (itemData: ItemData) => void;
    forgetExif: () => void;
}

class FileViewerDataSourceState {
    // Other viewer code assumes at most one active PhotoSwipe instance.
    viewerCount = 0;
    needsReset = false;
    itemDataByFileID = new Map<number, ItemData>();
    itemDataValidTillByFileID = new Map<number, Date>();
    needsRefreshByFileID = new Map<number, () => void>();
    fileInfoExifByFileID = new Map<number, FileInfoExif>();
    exifObserverByFileID = new Map<number, (exif: FileInfoExif) => void>();
}

export const createFileViewerDataSource = ({
    downloadManager,
    hlsPlaylistDataForFile,
    extractRawExif,
    parseExif,
}: FileViewerDataSourceDeps): FileViewerDataSource => {
    let _state = new FileViewerDataSourceState();

    const resetState = () => {
        _state = new FileViewerDataSourceState();
    };

    const logoutFileViewerDataSource = resetState;

    // Live callbacks make an immediate reset unsafe while the viewer is open.
    const resetFileViewerDataSourceOnClose = () => {
        if (_state.viewerCount) {
            _state.needsReset = true;
        } else {
            resetState();
        }
    };

    const fileViewerWillOpen = () => {
        _state.viewerCount++;
    };

    const fileViewerDidClose = () => {
        _state.viewerCount--;
        if (_state.needsReset && _state.viewerCount == 0) {
            resetState();
        } else {
            forgetFailedOrTransientItems();
            forgetExif();
        }
    };

    const itemDataForFile = (
        file: EnteFile,
        opts: ItemDataOpts | undefined,
        needsRefresh: () => void,
    ) => {
        const fileID = file.id;
        const fileType = file.metadata.fileType;

        const validTill = _state.itemDataValidTillByFileID.get(fileID);
        if (validTill && validTill < new Date()) {
            forgetItemDataForFileID(fileID);
        }

        let itemData = _state.itemDataByFileID.get(fileID);

        _state.needsRefreshByFileID.set(file.id, needsRefresh);

        if (!itemData) {
            itemData = { fileID, fileType, isContentLoading: true };
            _state.itemDataByFileID.set(file.id, itemData);
            void enqueueUpdates(file, opts);
        }

        return itemData;
    };

    const forgetItemDataForFileID = (fileID: number) => {
        _state.itemDataByFileID.delete(fileID);
        _state.itemDataValidTillByFileID.delete(fileID);
    };

    // Adjacent slides stay alive, so retry starts only after leaving preload range.
    const forgetItemDataForFileIDIfNeeded = (fileID: number) => {
        const itemData = _state.itemDataByFileID.get(fileID);
        if (itemData?.fetchFailed || itemData?.isTransient)
            forgetItemDataForFileID(fileID);
    };

    const updateItemDataAlt = (fileID: number, newAlt: string) => {
        const itemData = _state.itemDataByFileID.get(fileID);
        if (itemData) {
            itemData.alt = newAlt;
        }
    };

    const forgetFailedOrTransientItems = () =>
        [..._state.itemDataByFileID.keys()].forEach(
            forgetItemDataForFileIDIfNeeded,
        );

    const enqueueUpdates = async (
        file: EnteFile,
        opts: ItemDataOpts | undefined,
    ) => {
        const fileID = file.id;
        const fileType = file.metadata.fileType;

        const update = (itemData: Partial<ItemData>, validTill?: Date) => {
            const alt = file.pubMagicMetadata?.data.caption;

            _state.itemDataByFileID.set(file.id, {
                ...itemData,
                fileType,
                fileID,
                alt,
            });
            if (validTill) {
                _state.itemDataValidTillByFileID.set(file.id, validTill);
            } else {
                _state.itemDataValidTillByFileID.delete(file.id);
            }
            _state.needsRefreshByFileID.get(file.id)?.();
        };

        const updateVideo = (
            videoURL: string | undefined,
            hlsPlaylistData: HLSPlaylistDataForFile,
        ) => {
            const videoURLD = videoURL ? { videoURL } : {};
            if (typeof hlsPlaylistData == "object") {
                const {
                    playlistURL: videoPlaylistURL,
                    width,
                    height,
                } = hlsPlaylistData;
                update(
                    { ...videoURLD, videoPlaylistURL, width, height },
                    createHLSPlaylistItemDataValidity(),
                );
            } else {
                // "skip" is stable; undefined may become a playlist later.
                update({
                    ...videoURLD,
                    isTransient: hlsPlaylistData != "skip",
                });
            }
        };

        const markFailed = () => {
            const lastData: Partial<ItemData> =
                _state.itemDataByFileID.get(file.id) ?? {};
            delete lastData.isContentLoading;
            update({ ...lastData, fetchFailed: true });
        };

        try {
            const thumbnailURL =
                await downloadManager.renderableThumbnailURL(file);
            const thumbnailData = await withDimensionsIfPossible(
                ensureString(thumbnailURL),
            );

            const { width, height } = thumbnailDimensions(thumbnailData, file);

            update({
                ...thumbnailData,
                width,
                height,
                isContentLoading: true,
                isContentZoomable: false,
            });
        } catch (e) {
            log.error("Failed to fetch thumbnail", e);
            markFailed();
            return;
        }

        try {
            let hlsPlaylistData: HLSPlaylistDataForFile;
            if (file.metadata.fileType == FileType.video) {
                hlsPlaylistData = await hlsPlaylistDataForFile(
                    file,
                    downloadManager.publicAlbumsCredentials,
                );
                if (
                    typeof hlsPlaylistData == "object" &&
                    opts?.videoQuality != "original"
                ) {
                    updateVideo(undefined, hlsPlaylistData);
                    return;
                }
            }

            const sourceURLs = await downloadManager.renderableSourceURLs(file);

            switch (sourceURLs.type) {
                case "image": {
                    const { imageURL, originalImageBlob } = sourceURLs;
                    const itemData = await withDimensionsIfPossible(imageURL);
                    update({ ...itemData, imageURL, originalImageBlob });
                    break;
                }

                case "video": {
                    const { videoURL } = sourceURLs;
                    updateVideo(videoURL, hlsPlaylistData);
                    break;
                }

                case "livePhoto": {
                    // Resolve video first because the HEIC image conversion is slow.
                    const videoURL = await sourceURLs.videoURL();
                    update({
                        videoURL,
                        isContentLoading: true,
                        isContentZoomable: false,
                    });
                    const imageURL = await sourceURLs.imageURL();
                    const originalImageBlob = sourceURLs.originalImageBlob;
                    update({
                        ...(await withDimensionsIfPossible(imageURL)),
                        imageURL,
                        originalImageBlob,
                        videoURL,
                    });
                    break;
                }
            }
        } catch (e) {
            log.error("Failed to fetch file", e);
            markFailed();
        }
    };

    const withDimensionsIfPossible = (
        imageURL: string,
    ): Promise<Partial<ItemData>> =>
        new Promise((resolve) => {
            const image = new Image();
            image.onload = () =>
                resolve({
                    src: imageURL,
                    width: image.naturalWidth,
                    height: image.naturalHeight,
                });
            image.onerror = () => resolve({ src: imageURL });
            image.src = imageURL;
        });

    const thumbnailDimensions = (
        { width: thumbnailWidth, height: thumbnailHeight }: Partial<ItemData>,
        file: EnteFile,
    ) => {
        const { w: imageWidth, h: imageHeight } =
            file.pubMagicMetadata?.data ?? {};
        if (thumbnailWidth && thumbnailHeight && imageWidth && imageHeight) {
            const arThumb = thumbnailWidth / thumbnailHeight;
            const arImage = imageWidth / imageHeight;
            if (Math.abs(arThumb - arImage) < 0.1) {
                return { width: imageWidth, height: imageHeight };
            }
        }
        return { width: thumbnailWidth, height: thumbnailHeight };
    };
    // Museum's signed playlist URLs last seven days; expire them two days early.
    const createHLSPlaylistItemDataValidity = () =>
        new Date(Date.now() + 5 * 24 * 60 * 60 * 1000);
    const fileInfoExifForFile = (
        file: EnteFile,
        observer: (exifData: FileInfoExif) => void,
    ) => {
        const fileID = file.id;
        const exifData = _state.fileInfoExifByFileID.get(fileID);
        if (exifData) return exifData;

        _state.exifObserverByFileID.set(fileID, observer);
        return undefined;
    };

    const updateFileInfoExifIfNeeded = async (itemData: ItemData) => {
        const { fileID, fileType, originalImageBlob } = itemData;

        if (_state.fileInfoExifByFileID.has(fileID)) return;

        const update = (exifData: FileInfoExif) => {
            _state.fileInfoExifByFileID.set(fileID, exifData);
            _state.exifObserverByFileID.get(fileID)?.(exifData);
        };

        if (fileType == FileType.video) {
            update(createPlaceholderFileInfoExif());
            return;
        }

        if (!originalImageBlob) return;

        try {
            const file = new File([originalImageBlob], "");
            const tags = await extractRawExif(file);
            const parsed = parseExif(tags);
            update({ tags, parsed });
        } catch (e) {
            log.error("Failed to extract exif", e);
            update(createPlaceholderFileInfoExif());
        }
    };

    const createPlaceholderFileInfoExif = (): FileInfoExif => ({
        tags: undefined,
        parsed: undefined,
    });

    const forgetExifForItemData = ({ fileID }: ItemData) => {
        _state.fileInfoExifByFileID.delete(fileID);
        _state.exifObserverByFileID.delete(fileID);
    };

    const forgetExif = () => {
        _state.fileInfoExifByFileID.clear();
        _state.exifObserverByFileID.clear();
    };

    return {
        logoutFileViewerDataSource,
        resetFileViewerDataSourceOnClose,
        fileViewerWillOpen,
        fileViewerDidClose,
        itemDataForFile,
        forgetItemDataForFileID,
        forgetItemDataForFileIDIfNeeded,
        updateItemDataAlt,
        fileInfoExifForFile,
        updateFileInfoExifIfNeeded,
        forgetExifForItemData,
        forgetExif,
    };
};
