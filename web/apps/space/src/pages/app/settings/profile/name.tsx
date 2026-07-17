import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import React, { useEffect, useState } from "react";
import {
    ChangeNameSettingsScreen,
    settingsBackground,
} from "screens/SettingsScreen";
import {
    saveSpaceProfile,
    spaceProfileErrorMessage,
} from "services/spaceProfile";
import { useSpaceAppState } from "state/spaceAppState";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

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
                onBack={() => void router.push(spaceRoutes.settingsProfile)}
                onSave={(fullName) => {
                    setErrorMessage(undefined);
                    setIsSaving(true);
                    void saveSpaceProfile({ ...profile, fullName })
                        .then((savedProfile) => {
                            setProfile(savedProfile);
                            void router.push(spaceRoutes.settingsProfile);
                        })
                        .catch((error: unknown) => {
                            console.error("Space name update failed", error);
                            setErrorMessage(spaceProfileErrorMessage(error));
                        })
                        .finally(() => setIsSaving(false));
                }}
            />
        </>
    );
};

export default Page;
