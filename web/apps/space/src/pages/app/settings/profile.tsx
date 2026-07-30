import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import React, { useEffect } from "react";
import {
    ProfileSettingsScreen,
    settingsBackground,
} from "screens/SettingsScreen";
import { useSpaceAppState } from "state/spaceAppState";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const { profile, profileLoadError, profileLoadStatus } = useSpaceAppState();

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
            <ProfileSettingsScreen
                onBack={() => void router.push(spaceRoutes.settings)}
                onChangeCoverImage={() =>
                    void router.push(spaceRoutes.profileCoverFrom("settings"))
                }
                onChangeName={() =>
                    void router.push(spaceRoutes.settingsProfileName)
                }
                onChangeProfilePicture={() =>
                    void router.push(spaceRoutes.profilePhotoFrom("settings"))
                }
            />
        </>
    );
};

export default Page;
