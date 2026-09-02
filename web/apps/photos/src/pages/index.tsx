import { DevSettingsDialog } from "@/components/auth/DevSettingsDialog";
import { PhotosAuthShell } from "@/components/PhotosAuthShell";
import { LoginForm } from "ente-accounts/components/auth/LoginForm";
import { SignUpForm } from "ente-accounts/components/auth/SignUpForm";
import { LoginContents } from "ente-accounts/components/LoginContents";
import { SignUpContents } from "ente-accounts/components/SignUpContents";
import { savedPartialLocalUser } from "ente-accounts/services/accounts-db";
import { CenteredFill } from "ente-base/components/containers";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { useBaseContext } from "ente-base/context";
import {
    JOIN_ALBUM_CONTEXT_KEY,
    type JoinAlbumContext,
} from "ente-base/join-album";
import log from "ente-base/log";
import { customAPIHost } from "ente-base/origins";
import {
    masterKeyFromSession,
    updateSessionFromElectronSafeStorageIfNeeded,
} from "ente-base/session";
import { savedAuthToken } from "ente-base/token";
import { canAccessIndexedDB } from "ente-gallery/services/files-db";
import { DevSettings } from "ente-new/photos/components/DevSettings";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useState } from "react";

const Page: React.FC = () => {
    const { showMiniDialog } = useBaseContext();

    const [loading, setLoading] = useState(true);
    const [showLogin, setShowLogin] = useState(true);
    const [host, setHost] = useState<string | undefined>(undefined);

    const router = useRouter();

    const refreshHost = useCallback(
        () => void customAPIHost().then(setHost),
        [],
    );

    const handleShowLogin = useCallback(() => setShowLogin(true), []);
    const handleShowSignUp = useCallback(() => setShowLogin(false), []);

    useEffect(() => {
        void (async () => {
            refreshHost();
            const currentURL = new URL(window.location.href);

            // Persist join data before authentication redirects discard this URL.
            const joinAlbumParam = currentURL.searchParams.get("joinAlbum");
            if (joinAlbumParam && joinAlbumParam !== "true") {
                try {
                    const accessToken = joinAlbumParam;
                    const collectionIdParam =
                        currentURL.searchParams.get("collectionId");
                    const [collectionKeyHash, fragmentParams = ""] =
                        currentURL.hash.slice(1).split("&", 2);
                    const jwtFromURL =
                        new URLSearchParams(fragmentParams).get("jwt") ??
                        undefined;

                    if (accessToken && collectionKeyHash && collectionIdParam) {
                        const { extractCollectionKeyFromShareURL } =
                            await import("ente-gallery/services/share");

                        const tempURL = new URL(window.location.href);
                        tempURL.hash = collectionKeyHash;
                        const collectionKey =
                            await extractCollectionKeyFromShareURL(tempURL);

                        const context: JoinAlbumContext = {
                            accessToken,
                            collectionKey,
                            collectionKeyHash,
                            collectionID: parseInt(collectionIdParam, 10),
                            ...(jwtFromURL && { accessTokenJWT: jwtFromURL }),
                        };

                        sessionStorage.setItem(
                            JOIN_ALBUM_CONTEXT_KEY,
                            JSON.stringify(context),
                        );
                    }
                } catch (error) {
                    log.error(
                        "Failed to store join album context from URL",
                        error,
                    );
                    showMiniDialog({
                        title: t("error"),
                        message: t("generic_error_retry"),
                    });
                }
            }

            await updateSessionFromElectronSafeStorageIfNeeded();
            if ((await masterKeyFromSession()) && (await savedAuthToken())) {
                await router.push("/gallery");
            } else if (savedPartialLocalUser()?.email) {
                await router.push("/verify");
            }
            if (!(await canAccessIndexedDB())) {
                showMiniDialog({
                    title: t("error"),
                    message: t("local_storage_not_accessible"),
                    nonClosable: true,
                    cancel: false,
                });
            }
            setLoading(false);
        })();
    }, [showMiniDialog, router, refreshHost]);

    return (
        <TappableContainer onMaybeChangeHost={refreshHost}>
            {loading ? (
                <ActivityIndicator />
            ) : (
                <PhotosAuthShell>
                    {showLogin ? (
                        <LoginContents
                            {...{ host }}
                            onSignUp={handleShowSignUp}
                            presentation={LoginForm}
                        />
                    ) : (
                        <SignUpContents
                            {...{ router, host }}
                            onLogin={handleShowLogin}
                            presentation={SignUpForm}
                        />
                    )}
                </PhotosAuthShell>
            )}
        </TappableContainer>
    );
};

export default Page;

interface TappableContainerProps {
    onMaybeChangeHost: () => void;
}

const TappableContainer: React.FC<
    React.PropsWithChildren<TappableContainerProps>
> = ({ onMaybeChangeHost, children }) => {
    // Seven background taps open self-hosting settings outside Ente production.
    const [tapCount, setTapCount] = useState(0);
    const [showDevSettings, setShowDevSettings] = useState(false);

    const handleClick: React.MouseEventHandler = (event) => {
        if (!shouldAllowChangingAPIOrigin()) return;

        if (event.target instanceof HTMLButtonElement) return;

        if (showDevSettings) return;

        setTapCount(tapCount + 1);
        if (tapCount + 1 == 7) {
            setTapCount(0);
            setShowDevSettings(true);
        }
    };

    const handleClose = () => {
        setShowDevSettings(false);
        onMaybeChangeHost();
    };

    return (
        <CenteredFill
            sx={[
                {
                    bgcolor: "background.paper2",
                    "@media (width <= 1024px)": { flexDirection: "column" },
                },
                (theme) =>
                    theme.applyStyles("dark", {
                        bgcolor: "background.default",
                    }),
            ]}
            onClick={handleClick}
        >
            <DevSettings
                open={showDevSettings}
                onClose={handleClose}
                presentation={DevSettingsDialog}
            />
            {children}
        </CenteredFill>
    );
};

const shouldAllowChangingAPIOrigin = () => {
    const hostname = new URL(window.location.origin).hostname;
    return !(
        hostname.endsWith(".ente.com") ||
        hostname.endsWith(".ente.io") ||
        hostname.endsWith(".ente.sh")
    );
};
