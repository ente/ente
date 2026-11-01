import type { RemotePullOpts } from "@/components/gallery";
import { useSubscriptionCompletionRedirect } from "@/components/gallery/hooks/use-subscription-completion-redirect";
import { useGalleryReducer } from "@/components/gallery/reducer";
import exportService from "@/services/export";
import { processPendingAlbumJoin } from "@/services/join-album";
import { sessionExpiredDialogAttributes } from "ente-accounts/components/utils/dialog";
import {
    getAndClearIsFirstLogin,
    savedJustSignedUp,
} from "ente-accounts/services/accounts-db";
import { stashRedirect } from "ente-accounts/services/redirect";
import { isSessionInvalid } from "ente-accounts/services/session";
import { ensureLocalUser } from "ente-accounts/services/user";
import { useBaseContext } from "ente-base/context";
import { subscribeMainWindowFocus } from "ente-base/electron";
import { isNamedError } from "ente-base/error";
import { hasPendingAlbumToJoin } from "ente-base/join-album";
import log from "ente-base/log";
import {
    clearSessionStorage,
    haveMasterKeyInSession,
} from "ente-base/session-storage";
import { savedAuthToken } from "ente-base/token";
import { initContacts, pullContacts } from "ente-contacts";
import {
    usePeopleStateSnapshot,
    useUserDetailsSnapshot,
} from "ente-new/photos/components/utils/use-snapshot";
import { masterKeyFromSession } from "ente-new/photos/services/account-keys";
import { contactsGetDiff, contactsGetProfilePicture } from "ente-photos-wasm";

import { ensureAuthenticatedSession } from "@/services/authenticated-session";
import { postPullFiles, prePullFiles, pullFiles } from "@/services/pull";
import watcher from "@/services/watch";
import {
    savedCollectionFiles,
    savedCollections,
    savedTrashItems,
} from "ente-new/photos/services/photos-fdb";
import { updateSearchCollectionsAndFiles } from "ente-new/photos/services/search";
import { initSettings } from "ente-new/photos/services/settings";
import { savedUserDetailsOrTriggerPull } from "ente-new/photos/services/user-details";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { PromiseQueue } from "ente-utils/promise";
import { t } from "i18next";
import { useRouter } from "next/router";
import { useCallback, useEffect, useRef, useState } from "react";

export const useGalleryLibrary = () => {
    const { logout, showMiniDialog, onGenericError } = useBaseContext();
    const { showLoadingBar, hideLoadingBar } = usePhotosAppContext();
    const router = useRouter();
    const [state, dispatch] = useGalleryReducer();

    const [searchIndexRevision, setSearchIndexRevision] = useState(0);
    const [isFirstLoad, setIsFirstLoad] = useState(false);
    // Pull pipelines mutate the same local DB and reducer state.
    const remoteFilesPullQueue = useRef(new PromiseQueue<void>());
    const remotePullQueue = useRef(new PromiseQueue<void>());

    const userDetails = useUserDetailsSnapshot();
    const peopleState = usePeopleStateSnapshot();
    const showSessionExpiredDialog = useCallback(
        () => showMiniDialog(sessionExpiredDialogAttributes(logout)),
        [showMiniDialog, logout],
    );

    // Use this for collection/file/trash-only effects; a full pull costs more.
    const remoteFilesPull = useCallback(
        () =>
            remoteFilesPullQueue.current.add(() =>
                pullFiles({
                    onSetCollections: (collections) =>
                        dispatch({ type: "setCollections", collections }),
                    onSetCollectionFiles: (collectionFiles) =>
                        dispatch({
                            type: "setCollectionFiles",
                            collectionFiles,
                        }),
                    onSetTrashedItems: (trashItems) =>
                        dispatch({ type: "setTrashItems", trashItems }),
                    onDidUpdateCollectionFiles: () =>
                        exportService.onLocalFilesUpdated(),
                }),
            ),
        [],
    );

    const remotePull = useCallback(
        async (opts?: RemotePullOpts) =>
            remotePullQueue.current.add(async () => {
                const { silent, source, strict } = opts ?? {};

                if (!navigator.onLine) {
                    if (strict) throw new Error("Remote pull failed: offline");
                    return;
                }
                if (await isSessionInvalid()) {
                    showSessionExpiredDialog();
                    if (strict)
                        throw new Error("Remote pull failed: invalid session");
                    return;
                }
                if (!(await masterKeyFromSession())) {
                    clearSessionStorage();
                    void router.push("/credentials");
                    if (strict)
                        throw new Error(
                            "Remote pull failed: missing master key",
                        );
                    return;
                }

                try {
                    if (!silent) showLoadingBar();
                    await prePullFiles();
                    await remoteFilesPull();
                    await postPullFiles(source);
                } catch (e) {
                    // A later pull retries transient failures after remote mutations.
                    log.error("Remote pull failed", e);
                    if (strict) throw e;
                } finally {
                    dispatch({ type: "clearUnsyncedState" });
                    if (!silent) hideLoadingBar();
                }
            }),
        [
            showLoadingBar,
            hideLoadingBar,
            router,
            showSessionExpiredDialog,
            remoteFilesPull,
        ],
    );

    useEffect(() => {
        const electron = globalThis.electron;
        let syncIntervalID: ReturnType<typeof setInterval> | undefined;
        let unsubscribeMainWindowFocus: (() => void) | undefined;

        void (async () => {
            const authToken = await savedAuthToken();
            if (!haveMasterKeyInSession() || !authToken) {
                stashRedirect("/gallery");
                void router.push("/");
                return;
            }

            if (savedJustSignedUp()) {
                void router.replace("/plan");
                return;
            }

            try {
                await ensureAuthenticatedSession();
            } catch (e) {
                if (isNamedError(e, "missing_recovery_key")) {
                    showMiniDialog(sessionExpiredDialogAttributes(logout));
                } else {
                    onGenericError(e);
                }
                return;
            }

            initSettings();

            dispatch({ type: "showAll" });

            setIsFirstLoad(getAndClearIsFirstLogin());

            const user = ensureLocalUser();
            void initContacts(
                user.id,
                ensureAuthenticatedSession,
                contactsGetDiff,
                contactsGetProfilePicture,
            )
                .then(pullContacts)
                .catch((error: unknown) => {
                    log.warn(
                        "[gallery] Failed to warm contacts display cache",
                        error,
                    );
                });
            const userDetails = await savedUserDetailsOrTriggerPull();
            dispatch({
                type: "mount",
                user,
                familyData: userDetails?.familyData,
                collections: await savedCollections(),
                collectionFiles: await savedCollectionFiles(),
                trashItems: await savedTrashItems(),
            });

            // Join first so the initial pull includes the new album.
            let joinedAlbumId: number | null = null;

            if (hasPendingAlbumToJoin()) {
                try {
                    const joinedCollectionId = await processPendingAlbumJoin();
                    if (joinedCollectionId) {
                        joinedAlbumId = joinedCollectionId;
                    }
                } catch (error) {
                    log.error("Failed to join album", error);
                    showMiniDialog({
                        title: t("error"),
                        message: t("album_join_failed"),
                    });
                }
            }

            await remotePull({ source: "gallery-mount" });

            if (joinedAlbumId) {
                dispatch({
                    type: "showCollectionSummary",
                    collectionSummaryID: joinedAlbumId,
                });
            }

            setIsFirstLoad(false);

            syncIntervalID = setInterval(
                () => remotePull({ silent: true, source: "gallery-periodic" }),
                5 * 60 * 1000,
            );

            if (electron) {
                unsubscribeMainWindowFocus = subscribeMainWindowFocus(() => {
                    void remotePull({ silent: true, source: "desktop-focus" });
                    void watcher.checkAccessibility();
                });
            }
        })();

        return () => {
            clearInterval(syncIntervalID);
            unsubscribeMainWindowFocus?.();
        };
    }, []);

    useEffect(() => {
        if (state.user && userDetails) {
            dispatch({ type: "setUserDetails", userDetails });
        }
    }, [state.user, userDetails]);

    useEffect(() => {
        updateSearchCollectionsAndFiles(
            state.collections,
            state.collectionFiles,
            state.hiddenCollectionIDs,
            state.hiddenFileIDs,
        );
        setSearchIndexRevision((revision) => revision + 1);
    }, [
        state.collections,
        state.collectionFiles,
        state.hiddenCollectionIDs,
        state.hiddenFileIDs,
    ]);

    useEffect(() => {
        dispatch({ type: "setPeopleState", peopleState });
    }, [peopleState]);

    useSubscriptionCompletionRedirect();
    return {
        state,
        dispatch,
        isFirstLoad,
        searchIndexRevision,
        peopleState,
        remotePull,
        remoteFilesPull,
        showSessionExpiredDialog,
    };
};
