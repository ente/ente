import {
    fileViewerDidClose,
    fileViewerWillOpen,
    forgetExifForItemData,
    forgetItemDataForFileID,
    forgetItemDataForFileIDIfNeeded,
    itemDataForFile,
    updateFileInfoExifIfNeeded,
} from "./data-source";
import {
    FileViewerPhotoSwipe as FileViewerPhotoSwipeCore,
    moreButtonID,
    moreMenuID,
    resetMoreMenuButtonOnMenuClose,
    type FileViewerPhotoSwipeAnnotatedFile,
    type FileViewerPhotoSwipeCoreOptions,
    type FileViewerPhotoSwipeDataSource,
    type FileViewerPhotoSwipeDelegate,
} from "./photoswipe-core";

export type FileViewerPhotoSwipeOptions<
    T extends FileViewerPhotoSwipeAnnotatedFile =
        FileViewerPhotoSwipeAnnotatedFile,
> = Omit<
    FileViewerPhotoSwipeCoreOptions<T>,
    "dataSource" | "isPublicAlbum" | "publicAlbumLogoHTML"
>;

const fileViewerPhotoSwipeDataSource = {
    fileViewerDidClose,
    fileViewerWillOpen,
    forgetExifForItemData,
    forgetItemDataForFileID,
    forgetItemDataForFileIDIfNeeded,
    itemDataForFile,
    updateFileInfoExifIfNeeded,
} satisfies FileViewerPhotoSwipeDataSource;

export class FileViewerPhotoSwipe<
    T extends FileViewerPhotoSwipeAnnotatedFile =
        FileViewerPhotoSwipeAnnotatedFile,
> extends FileViewerPhotoSwipeCore<T> {
    constructor(options: FileViewerPhotoSwipeOptions<T>) {
        super({ ...options, dataSource: fileViewerPhotoSwipeDataSource });
    }
}

export { moreButtonID, moreMenuID, resetMoreMenuButtonOnMenuClose };
export type {
    FileViewerPhotoSwipeAnnotatedFile,
    FileViewerPhotoSwipeDataSource,
    FileViewerPhotoSwipeDelegate,
};
