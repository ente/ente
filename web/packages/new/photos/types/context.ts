import type { NotificationAttributes } from "ente-base/components/Notification";
import { createContext, useContext } from "react";

export interface PhotosAppContextT {
    showLoadingBar: () => void;
    hideLoadingBar: () => void;
    showNotification: (attributes: NotificationAttributes) => void;
    watchFolderView: boolean;
    setWatchFolderView: (isOpen: boolean) => void;
    setIsFileViewerOpen?: (isOpen: boolean) => void;
}

export const PhotosAppContext = createContext<PhotosAppContextT | undefined>(
    undefined,
);

export const usePhotosAppContext = (): PhotosAppContextT =>
    useContext(PhotosAppContext)!;
