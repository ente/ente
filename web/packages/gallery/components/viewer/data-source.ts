import { downloadManager } from "ente-gallery/services/download";
import { extractRawExif, parseExif } from "ente-gallery/services/exif";
import { hlsPlaylistDataForFile } from "ente-gallery/services/video";
import { createFileViewerDataSource, type ItemData } from "./data-source-core";

export type { ItemData };

export const {
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
} = createFileViewerDataSource({
    downloadManager,
    hlsPlaylistDataForFile,
    extractRawExif,
    parseExif,
});
