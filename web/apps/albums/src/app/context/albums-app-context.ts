import type { NotificationAttributes } from "ente-base/components/Notification";
import { createContext, useContext } from "react";

/**
 * The type of the React context available to all pages in the albums app.
 */
export interface AlbumsAppContextT {
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
     * Show a {@link Notification}, customizing its contents and click
     * behaviour using the provided {@link NotificationAttributes}.
     */
    showNotification: (attributes: NotificationAttributes) => void;
}

/**
 * The React {@link Context} available to all nodes in the React tree of albums
 * app pages.
 */
export const AlbumsAppContext = createContext<AlbumsAppContextT | undefined>(
    undefined,
);

/**
 * Utility hook to get the albums app context.
 *
 * This context is provided at the top level _app component for the albums app,
 * and thus is available to all React components in the albums app's React
 * tree.
 */
export const useAlbumsAppContext = (): AlbumsAppContextT =>
    useContext(AlbumsAppContext)!;
