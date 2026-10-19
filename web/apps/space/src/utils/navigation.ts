import { spaceRoutes } from "utils/routes";

export const spaceUnreadStatusChangedEvent = "space-unread-status-changed";

export const spaceNavigationDestination = (pathname: string) => {
    if (
        pathname == spaceRoutes.notifications ||
        pathname == spaceRoutes.profile ||
        pathname.startsWith(`${spaceRoutes.profile}/`)
    )
        return undefined;
    if (pathname == spaceRoutes.friendPage) return spaceRoutes.friends;
    for (const destination of [spaceRoutes.friends, spaceRoutes.messages]) {
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
