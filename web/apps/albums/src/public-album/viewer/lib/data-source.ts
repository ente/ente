import { downloadManager } from "@/public-album/download/services/download-manager";
import { hlsPlaylistDataForFile } from "@/public-album/media/video/preview";
import {
    createFileViewerDataSource,
    type ItemData,
    type ItemDataOpts,
} from "ente-gallery/components/viewer/data-source-core";
import { extractRawExif, parseExif } from "ente-gallery/services/exif";

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
