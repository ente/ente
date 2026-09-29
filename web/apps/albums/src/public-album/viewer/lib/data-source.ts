import { downloadManager } from "@/public-album/download/services/download-manager";
import { hlsPlaylistDataForFile } from "@/public-album/media/video/preview";
import {
    createFileViewerDataSource,
    type ItemData,
} from "ente-gallery/components/viewer/data-source-core";
import { extractRawExif, parseExif } from "ente-gallery/services/exif";

export type { ItemData };

export const {
    fileViewerWillOpen,
    fileViewerDidClose,
    itemDataForFile,
    forgetItemDataForFileID,
    forgetItemDataForFileIDIfNeeded,
    fileInfoExifForFile,
    updateFileInfoExifIfNeeded,
    forgetExifForItemData,
} = createFileViewerDataSource({
    downloadManager,
    hlsPlaylistDataForFile,
    extractRawExif,
    parseExif,
});
