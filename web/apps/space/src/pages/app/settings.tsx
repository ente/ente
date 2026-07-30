import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import React, { useEffect } from "react";
import { SettingsScreen, settingsBackground } from "screens/SettingsScreen";
import { spaceLogout } from "services/spaceLogout";
import { useSpaceAppState } from "state/spaceAppState";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const { profile, profileLoadError, profileLoadStatus, resetAfterLogout } =
        useSpaceAppState();

    useEffect(() => {
        if (profileLoadStatus == "ready" && !profile) {
            void router.replace(spaceRoutes.onboarding);
        }
    }, [profile, profileLoadStatus, router]);

    if (profileLoadStatus != "ready" || !profile) {
        return (
            <SpaceRouteFallback
                background={settingsBackground}
                message={profileLoadError}
            />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={settingsBackground} />
            <SettingsScreen
                onBack={() => void router.push(spaceRoutes.profile)}
                onChangeCoverImage={() =>
                    void router.push(spaceRoutes.profileCoverFrom("settings"))
                }
                onChangeName={() =>
                    void router.push(spaceRoutes.settingsProfileName)
                }
                onChangeProfilePicture={() =>
                    void router.push(spaceRoutes.profilePhotoFrom("settings"))
                }
                onLogout={async () => {
                    await spaceLogout();
                    resetAfterLogout();
                    await router.push(spaceRoutes.onboarding);
                }}
            />
        </>
    );
};

export default Page;
