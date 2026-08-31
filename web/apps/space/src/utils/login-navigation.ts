import log from "ente-base/log";
import type { NextRouter } from "next/router";
import type { SpaceAppState } from "state/app-state";
import { sendPendingSpaceFriendRequest } from "utils/pending-friend-request";
import { spaceRoutes } from "utils/routes";

type RefreshProfile = SpaceAppState["refreshProfile"];

export const routeAfterCompletedLogin = async (
    router: NextRouter,
    refreshProfile: RefreshProfile,
    mode: "push" | "replace" = "push",
) => {
    const routeTo = (route: string) =>
        mode == "replace" ? router.replace(route) : router.push(route);
    let profile: Awaited<ReturnType<RefreshProfile>>;
    try {
        profile = await refreshProfile({ throwOnError: true });
    } catch {
        await routeTo(spaceRoutes.onboarding);
        return;
    }

    if (profile) {
        await sendPendingSpaceFriendRequest().catch((error: unknown) =>
            log.error("Failed to send pending friend request", error),
        );
        await routeTo(spaceRoutes.home);
        return;
    }

    await routeTo(spaceRoutes.createProfile("login"));
};
