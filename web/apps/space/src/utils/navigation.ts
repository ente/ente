import { spaceRoutes } from "utils/routes";

export const spaceUnreadStatusChangedEvent = "space-unread-status-changed";

export const spaceNavigationDestination = (pathname: string) => {
    if (pathname == spaceRoutes.friendPage) return spaceRoutes.friends;
    for (const destination of [
        spaceRoutes.friends,
        spaceRoutes.messages,
        spaceRoutes.profile,
    ]) {
        if (pathname == destination || pathname.startsWith(`${destination}/`))
            return destination;
    }
    if (
        pathname == spaceRoutes.home ||
        pathname.startsWith(`${spaceRoutes.home}/`)
    )
        return spaceRoutes.home;
    return undefined;
};
