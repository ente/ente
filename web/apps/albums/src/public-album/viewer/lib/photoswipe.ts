import {
    enteWordmarkSVGHTML,
    enteWordmarkViewBox,
} from "ente-base/components/ente-wordmark";
import {
    FileViewerPhotoSwipe as FileViewerPhotoSwipeCore,
    moreButtonID,
    moreMenuID,
    resetMoreMenuButtonOnMenuClose,
    type FileViewerPhotoSwipeAnnotatedFile,
    type FileViewerPhotoSwipeCoreOptions,
    type FileViewerPhotoSwipeDataSource,
    type FileViewerPhotoSwipeDelegate,
} from "ente-gallery/components/viewer/photoswipe-core";
import {
    fileViewerDidClose,
    fileViewerWillOpen,
    forgetExifForItemData,
    forgetItemDataForFileID,
    forgetItemDataForFileIDIfNeeded,
    itemDataForFile,
    updateFileInfoExifIfNeeded,
} from "./data-source";

export type FileViewerPhotoSwipeOptions<
    T extends FileViewerPhotoSwipeAnnotatedFile =
        FileViewerPhotoSwipeAnnotatedFile,
> = Omit<
    FileViewerPhotoSwipeCoreOptions<T>,
    "dataSource" | "haveUser" | "isPublicAlbum" | "publicAlbumLogoHTML"
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

const publicAlbumLogoHTML = `
<svg class="pswp__ente-logo-svg" viewBox="${enteWordmarkViewBox}" xmlns="http://www.w3.org/2000/svg">
  ${enteWordmarkSVGHTML}
</svg>
`;

export class FileViewerPhotoSwipe<
    T extends FileViewerPhotoSwipeAnnotatedFile =
        FileViewerPhotoSwipeAnnotatedFile,
> extends FileViewerPhotoSwipeCore<T> {
    constructor(options: FileViewerPhotoSwipeOptions<T>) {
        super({
            ...options,
            dataSource: fileViewerPhotoSwipeDataSource,
            haveUser: false,
            isPublicAlbum: true,
            publicAlbumLogoHTML,
        });
    }
}

export { moreButtonID, moreMenuID, resetMoreMenuButtonOnMenuClose };
export type {
    FileViewerPhotoSwipeAnnotatedFile,
    FileViewerPhotoSwipeDataSource,
    FileViewerPhotoSwipeDelegate,
};
