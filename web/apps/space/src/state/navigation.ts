import React from "react";
import type { SpaceUnreadStatus } from "services/space";

export const emptySpaceUnreadStatus: SpaceUnreadStatus = {
    messagesUnread: false,
    notificationsUnread: false,
};

export const SpaceUnreadStatusContext = React.createContext(
    emptySpaceUnreadStatus,
);

export const useSpaceUnreadStatus = () =>
    React.useContext(SpaceUnreadStatusContext);
