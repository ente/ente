import type { NextRouter } from "next/router";
import type { SpaceAppState } from "state/spaceAppState";
import { acceptPendingSpaceInvite } from "utils/spacePendingInvite";
import { spaceRoutes } from "utils/spaceRoutes";

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
        await acceptPendingSpaceInvite().catch((error: unknown) =>
            console.error("Failed to accept pending invite", error),
        );
        await routeTo(spaceRoutes.home);
        return;
    }

    await routeTo(spaceRoutes.createProfile("login"));
};
