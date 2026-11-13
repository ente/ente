import type { NotificationAttributes } from "ente-base/components/Notification";
import { createContext, useContext } from "react";

export interface AlbumsAppContextT {
    showLoadingBar: () => void;
    hideLoadingBar: () => void;
    showNotification: (attributes: NotificationAttributes) => void;
}

export const AlbumsAppContext = createContext<AlbumsAppContextT | undefined>(
    undefined,
);

export const useAlbumsAppContext = (): AlbumsAppContextT =>
    useContext(AlbumsAppContext)!;
