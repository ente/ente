import { SpacePageMeta } from "components/PageMeta";
import { SpaceRouteFallback } from "components/RouteFallback";
import React, { useEffect } from "react";
import { SettingsScreen, settingsBackground } from "screens/SettingsScreen";
import { spaceLogout } from "services/logout";
import { useSpaceAppState } from "state/app-state";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

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
