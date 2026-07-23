import type { NotificationAttributes } from "ente-base/components/Notification";
import { createContext, useContext } from "react";

/**
 * The type of the React context available to all pages in the photos app.
 */
export interface PhotosAppContextT {
    /**
     * Show the global activity indicator (a loading bar at the top of the
     * page).
     */
    showLoadingBar: () => void;
    /**
     * Hide the global activity indicator bar.
     */
    hideLoadingBar: () => void;
    /**
     * Show a {@link Notification}, customizing its contents and click behaviour
     * using the provided {@link NotificationAttributes}.
     */
    showNotification: (attributes: NotificationAttributes) => void;
    watchFolderView: boolean;
    setWatchFolderView: (isOpen: boolean) => void;
}

/**
 * The React {@link Context} available to all nodes in the React tree of photos
 * app pages.
 */
export const PhotosAppContext = createContext<PhotosAppContextT | undefined>(
    undefined,
);

/**
 * Utility hook to get the photos {@link PhotosAppContextT}.
 *
 * This context is provided at the top level _app component for the photos app,
 * and thus is available to all React components in the Photos app's React tree.
 */
export const usePhotosAppContext = (): PhotosAppContextT =>
    useContext(PhotosAppContext)!;
