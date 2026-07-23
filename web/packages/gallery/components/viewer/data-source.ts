import { downloadManager } from "ente-gallery/services/download";
import { extractRawExif, parseExif } from "ente-gallery/services/exif";
import { hlsPlaylistDataForFile } from "ente-gallery/services/video";
import {
    createFileViewerDataSource,
    type ItemData,
    type ItemDataOpts,
} from "./data-source-core";

export type { ItemData, ItemDataOpts };

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
    forgetExif,
} = createFileViewerDataSource({
    downloadManager,
    hlsPlaylistDataForFile,
    extractRawExif,
    parseExif,
});
