import { masterKeyFromSession } from "@/services/account-keys";
import { openAuthenticatedSession } from "@/services/authenticated-session";
import type { LockerUploadLimitState } from "@/services/locker-limits";
import {
    loadPersistedLockerState,
    syncLockerState,
} from "@/services/sync/sync";
import { loadLockerUsage, loadUserEmail } from "@/services/user-details";
import type { LockerCollection, LockerItem } from "@/types";
import { sessionExpiredDialogAttributes } from "ente-accounts/components/utils/dialog";
import {
    isSavedUserTokenMismatch,
    savedLocalUser,
    savedPartialLocalUser,
} from "ente-accounts/services/accounts-db";
import { stashRedirect } from "ente-accounts/services/redirect";
import { ensureLocalUser } from "ente-accounts/services/user";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import { isNamedError } from "ente-base/error";
import { authenticatedRequestHeaders, isHTTP401Error } from "ente-base/http";
import log from "ente-base/log";
import { savedAuthToken } from "ente-base/token";
import { ensureContactsReady } from "ente-contacts";
import { contactsGetDiff, contactsGetProfilePicture } from "ente-locker-wasm";
import { t } from "i18next";
import type { NextRouter } from "next/router";
import { useCallback, useEffect, useRef, useState } from "react";

interface UserDetails extends LockerUploadLimitState {
    email: string;
}

interface UseLockerDataProps {
    router: NextRouter;
    logout: () => void | Promise<void>;
    showMiniDialog: (attributes: MiniDialogAttributes) => void;
}

interface UserDetailsRefreshTrigger {
    collectionsSinceTime: number;
    trashSinceTime: number;
}

interface UploadLimitStateSnapshot {
    userDetails: UserDetails;
}

export const useLockerData = ({
    router,
    logout,
    showMiniDialog,
}: UseLockerDataProps) => {
    const [collections, setCollections] = useState<LockerCollection[]>([]);
    const [masterKey, setMasterKey] = useState<string | undefined>();
    const [hasFetched, setHasFetched] = useState(false);
    const [initialLoadError, setInitialLoadError] = useState<string | null>(
        null,
    );
    const [userDetails, setUserDetails] = useState<UserDetails | undefined>();
    const [trashItems, setTrashItems] = useState<LockerItem[]>([]);
    const [trashLastUpdatedAt, setTrashLastUpdatedAt] = useState(0);

    const mountedRef = useRef(true);
    const latestDataRequestRef = useRef(0);
    const latestUserDetailsRequestRef = useRef(0);
    const lastUserDetailsRefreshKeyRef = useRef<string | undefined>(undefined);
    const pendingUserDetailsRefreshRef = useRef<
        UserDetailsRefreshTrigger | undefined
    >(undefined);
    const isRefreshingUserDetailsRef = useRef(false);
    const userDetailsRef = useRef<UserDetails | undefined>(undefined);

    useEffect(
        () => () => {
            mountedRef.current = false;
        },
        [],
    );

    useEffect(() => {
        userDetailsRef.current = userDetails;
    }, [userDetails]);

    const warmContacts = useCallback(async () => {
        const [authToken, masterKey] = await Promise.all([
            savedAuthToken(),
            masterKeyFromSession(),
        ]);
        if (!authToken || !masterKey) return;

        const userID = ensureLocalUser().id;
        const session = await openAuthenticatedSession(
            userID,
            authToken,
            masterKey,
        );
        await ensureContactsReady(
            userID,
            session,
            contactsGetDiff,
            contactsGetProfilePicture,
        );
    }, []);

    const loadUserDetails = useCallback(async (): Promise<boolean> => {
        const requestID = ++latestUserDetailsRequestRef.current;
        try {
            const headers = await authenticatedRequestHeaders();
            const [lockerUsage, email] = await Promise.all([
                loadLockerUsage(headers),
                loadUserEmail(headers),
            ]);
            const nextUserDetails = { ...lockerUsage.userDetails, email };
            if (
                !mountedRef.current ||
                requestID !== latestUserDetailsRequestRef.current
            ) {
                return false;
            }

            setUserDetails(nextUserDetails);
            return true;
        } catch (error) {
            log.error("Failed to fetch user details", error);
            return false;
        }
    }, []);

    const refreshUserDetailsForSyncState = useCallback(
        async (trigger: UserDetailsRefreshTrigger) => {
            const key = `${trigger.collectionsSinceTime}:${trigger.trashSinceTime}`;
            if (key === lastUserDetailsRefreshKeyRef.current) {
                return;
            }
            if (isRefreshingUserDetailsRef.current) {
                pendingUserDetailsRefreshRef.current = trigger;
                return;
            }

            isRefreshingUserDetailsRef.current = true;
            let pendingTrigger: UserDetailsRefreshTrigger | undefined;
            try {
                const applied = await loadUserDetails();
                if (applied) {
                    lastUserDetailsRefreshKeyRef.current = key;
                }
            } finally {
                isRefreshingUserDetailsRef.current = false;
                pendingTrigger = pendingUserDetailsRefreshRef.current;
                pendingUserDetailsRefreshRef.current = undefined;
            }

            if (!pendingTrigger) {
                return;
            }

            const pendingKey = `${pendingTrigger.collectionsSinceTime}:${pendingTrigger.trashSinceTime}`;
            if (pendingKey !== lastUserDetailsRefreshKeyRef.current) {
                void refreshUserDetailsForSyncState(pendingTrigger);
            }
        },
        [loadUserDetails],
    );

    const ensureUploadLimitState = useCallback(async () => {
        if (userDetailsRef.current) {
            return {
                userDetails: userDetailsRef.current,
            } satisfies UploadLimitStateSnapshot;
        }

        try {
            const lockerUsage = await loadLockerUsage();
            return {
                userDetails: {
                    ...lockerUsage.userDetails,
                    email: savedLocalUser()?.email ?? "",
                },
            } satisfies UploadLimitStateSnapshot;
        } catch (error) {
            log.error("Failed to fetch locker upload limit state", error);
            return undefined;
        }
    }, []);

    const fetchAndStoreLockerData = useCallback(async () => {
        const requestID = ++latestDataRequestRef.current;

        const data = await syncLockerState();

        if (!mountedRef.current || requestID !== latestDataRequestRef.current) {
            return;
        }

        setCollections(data.collections);
        setTrashItems(data.trashItems);
        setTrashLastUpdatedAt(data.trashLastUpdatedAt);
        setInitialLoadError(null);
        void refreshUserDetailsForSyncState(data);
    }, [refreshUserDetailsForSyncState]);

    const refreshData = useCallback(async () => {
        if (!masterKey) {
            return;
        }

        try {
            await fetchAndStoreLockerData();
        } catch (error) {
            log.error("Failed to refresh locker data", error);
            if (isHTTP401Error(error)) {
                showMiniDialog(sessionExpiredDialogAttributes(logout));
            }
        }
    }, [fetchAndStoreLockerData, logout, masterKey, showMiniDialog]);

    useEffect(() => {
        let cancelled = false;
        const canApplyState = () => !cancelled && mountedRef.current;

        const load = async () => {
            try {
                const [mk, token, tokenMismatch] = await Promise.all([
                    masterKeyFromSession(),
                    savedAuthToken(),
                    isSavedUserTokenMismatch(),
                ]);
                if (tokenMismatch || !token) {
                    void logout();
                    return;
                }
                if (!mk) {
                    stashRedirect(router.asPath || "/");
                    void router.push(
                        savedPartialLocalUser()?.email ? "/verify" : "/login",
                    );
                    return;
                }

                await openAuthenticatedSession(ensureLocalUser().id, token, mk);
                if (!canApplyState()) {
                    return;
                }

                setMasterKey(mk);
                void warmContacts().catch((error: unknown) => {
                    log.warn(
                        "[locker] Failed to warm contacts display cache",
                        error,
                    );
                });

                const persisted = await loadPersistedLockerState();
                if (canApplyState() && persisted.hasPersistedState) {
                    setCollections(persisted.collections);
                    setTrashItems(persisted.trashItems);
                    setTrashLastUpdatedAt(persisted.trashLastUpdatedAt);
                    setInitialLoadError(null);
                    setHasFetched(true);
                    void refreshUserDetailsForSyncState(persisted);
                }

                await fetchAndStoreLockerData();
                if (canApplyState()) {
                    setHasFetched(true);
                }
            } catch (error) {
                log.error("Failed to fetch locker data", error);
                if (isNamedError(error, "missing_recovery_key")) {
                    showMiniDialog(sessionExpiredDialogAttributes(logout));
                    return;
                }
                if (isHTTP401Error(error)) {
                    showMiniDialog(sessionExpiredDialogAttributes(logout));
                }
                if (canApplyState()) {
                    setInitialLoadError(
                        error instanceof Error
                            ? t("failedToLoadCollections", {
                                  error: error.message,
                              })
                            : t("generic_error_retry"),
                    );
                    setHasFetched(true);
                }
            }
        };

        void load();

        return () => {
            cancelled = true;
        };
    }, [fetchAndStoreLockerData, logout, router, showMiniDialog, warmContacts]);

    const removeCollectionFromState = useCallback((collectionID: number) => {
        setCollections((current) =>
            current.filter((collection) => collection.id !== collectionID),
        );
    }, []);

    return {
        collections,
        hasFetched,
        initialLoadError,
        masterKey,
        refreshData,
        removeCollectionFromState,
        trashItems,
        trashLastUpdatedAt,
        userDetails,
        ensureUploadLimitState,
        warmContacts,
    };
};
