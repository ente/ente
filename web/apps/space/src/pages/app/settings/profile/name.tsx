import { SpacePageMeta } from "components/PageMeta";
import { SpaceRouteFallback } from "components/RouteFallback";
import log from "ente-base/log";
import React, { useEffect, useState } from "react";
import {
    ChangeNameSettingsScreen,
    settingsBackground,
} from "screens/SettingsScreen";
import { saveSpaceProfile, spaceProfileErrorMessage } from "services/profile";
import { useSpaceAppState } from "state/app-state";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const { profile, profileLoadError, profileLoadStatus, setProfile } =
        useSpaceAppState();
    const [errorMessage, setErrorMessage] = useState<string>();
    const [isSaving, setIsSaving] = useState(false);

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
            <ChangeNameSettingsScreen
                errorMessage={errorMessage}
                initialName={profile.fullName}
                isSaving={isSaving}
                onBack={() => void router.push(spaceRoutes.settings)}
                onSave={(fullName) => {
                    setErrorMessage(undefined);
                    setIsSaving(true);
                    void saveSpaceProfile({ ...profile, fullName })
                        .then((savedProfile) => {
                            setProfile(savedProfile);
                            void router.push(spaceRoutes.settings);
                        })
                        .catch((error: unknown) => {
                            log.error("Space name update failed", error);
                            setErrorMessage(spaceProfileErrorMessage(error));
                        })
                        .finally(() => setIsSaving(false));
                }}
            />
        </>
    );
};

export default Page;
