import {
    LOCKER_FILE_LIMIT_FREE,
    LOCKER_FILE_LIMIT_PAID,
    type LockerUploadLimitState,
} from "@/services/locker-limits";
import { loadPersistedLockerState, syncLockerState } from "@/services/remote";
import type { LockerCollection, LockerItem } from "@/types";
import { sessionExpiredDialogAttributes } from "ente-accounts-rs/components/utils/dialog";
import {
    isSavedUserTokenMismatch,
    savedLocalUser,
    savedPartialLocalUser,
} from "ente-accounts-rs/services/accounts-db";
import { stashRedirect } from "ente-accounts-rs/services/redirect";
import { masterKeyFromSession } from "ente-accounts-rs/services/session-storage";
import { ensureLocalUser } from "ente-accounts-rs/services/user";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import {
    authenticatedRequestHeaders,
    ensureOk,
    isHTTP401Error,
} from "ente-base/http";
import log from "ente-base/log";
import { apiURL } from "ente-base/origins";
import { savedAuthToken } from "ente-base/token";
import { ensureContactsReady } from "ente-contacts-web";
import { t } from "i18next";
import type { NextRouter } from "next/router";
import { useCallback, useEffect, useRef, useState } from "react";

interface LockerUserProfileResponse {
    email?: string;
}

interface LockerUsageResponse {
    isPaid?: boolean;
    isFamily?: boolean;
    usedFileCount?: number;
    fileLimit?: number;
    remainingFileCount?: number;
    usedStorage?: number;
    storageLimit?: number;
    remainingStorage?: number;
    userFileCount?: number;
    userStorage?: number;
}

export interface UserDetails extends LockerUploadLimitState {
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

interface LoadUserDetailsResult {
    applied: boolean;
    snapshot?: UploadLimitStateSnapshot;
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

    const loadLockerUsage = useCallback(
        async (
            headers?: Awaited<ReturnType<typeof authenticatedRequestHeaders>>,
        ) => {
            const requestHeaders =
                headers ?? (await authenticatedRequestHeaders());
            const lockerUsageRes = await fetch(
                await apiURL("/users/locker-usage"),
                { headers: requestHeaders },
            );
            ensureOk(lockerUsageRes);
            const lockerUsage =
                (await lockerUsageRes.json()) as LockerUsageResponse;

            const isFamily = !!lockerUsage.isFamily;
            return {
                userDetails: {
                    usage: lockerUsage.usedStorage ?? 0,
                    storageLimit: lockerUsage.storageLimit ?? 0,
                    fileCount: isFamily
                        ? (lockerUsage.userFileCount ?? 0)
                        : (lockerUsage.usedFileCount ?? 0),
                    lockerFileLimit:
                        lockerUsage.fileLimit ??
                        (lockerUsage.isPaid
                            ? LOCKER_FILE_LIMIT_PAID
                            : LOCKER_FILE_LIMIT_FREE),
                    isPartOfFamily: isFamily,
                    lockerFamilyFileCount: isFamily
                        ? (lockerUsage.usedFileCount ?? 0)
                        : undefined,
                },
            };
        },
        [],
    );

    const loadUserEmail = useCallback(
        async (
            headers?: Awaited<ReturnType<typeof authenticatedRequestHeaders>>,
        ) => {
            const requestHeaders =
                headers ?? (await authenticatedRequestHeaders());
            const userProfileRes = await fetch(
                await apiURL("/users/details/v2", { memoryCount: false }),
                { headers: requestHeaders },
            );
            ensureOk(userProfileRes);
            const userProfile =
                (await userProfileRes.json()) as LockerUserProfileResponse;
            return userProfile.email ?? savedLocalUser()?.email ?? "";
        },
        [],
    );

    const loadUserDetails =
        useCallback(async (): Promise<LoadUserDetailsResult> => {
            const requestID = ++latestUserDetailsRequestRef.current;
            try {
                const headers = await authenticatedRequestHeaders();
                const [lockerUsage, email] = await Promise.all([
                    loadLockerUsage(headers),
                    loadUserEmail(headers),
                ]);
                const nextUserDetails = { ...lockerUsage.userDetails, email };
                const snapshot = {
                    userDetails: nextUserDetails,
                } satisfies UploadLimitStateSnapshot;

                if (
                    !mountedRef.current ||
                    requestID !== latestUserDetailsRequestRef.current
                ) {
                    return { applied: false, snapshot };
                }

                setUserDetails(nextUserDetails);
                return { applied: true, snapshot };
            } catch (error) {
                log.error("Failed to fetch user details", error);
                return { applied: false };
            }
        }, [loadLockerUsage, loadUserEmail]);

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
                const result = await loadUserDetails();
                if (result.applied) {
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
    }, [loadLockerUsage]);

    const fetchAndStoreLockerData = useCallback(
        async (key: string) => {
            const requestID = ++latestDataRequestRef.current;

            const data = await syncLockerState(key);

            if (
                !mountedRef.current ||
                requestID !== latestDataRequestRef.current
            ) {
                return;
            }

            setCollections(data.collections);
            setTrashItems(data.trashItems);
            setTrashLastUpdatedAt(data.trashLastUpdatedAt);
            setInitialLoadError(null);
            void refreshUserDetailsForSyncState(data);
        },
        [refreshUserDetailsForSyncState],
    );

    const refreshData = useCallback(
        async (mk?: string) => {
            const key = mk ?? masterKey;
            if (!key) {
                return;
            }

            try {
                await fetchAndStoreLockerData(key);
            } catch (error) {
                log.error("Failed to refresh locker data", error);
                if (isHTTP401Error(error)) {
                    showMiniDialog(sessionExpiredDialogAttributes(logout));
                }
            }
        },
        [fetchAndStoreLockerData, logout, masterKey, showMiniDialog],
    );

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
                if (!canApplyState()) {
                    return;
                }

                setMasterKey(mk);
                void ensureContactsReady({
                    userID: ensureLocalUser().id,
                    masterKeyB64: mk,
                }).catch((error: unknown) => {
                    log.warn(
                        "[locker] Failed to warm contacts display cache",
                        error,
                    );
                });

                const persisted = await loadPersistedLockerState(mk);
                if (canApplyState() && persisted.hasPersistedState) {
                    setCollections(persisted.collections);
                    setTrashItems(persisted.trashItems);
                    setTrashLastUpdatedAt(persisted.trashLastUpdatedAt);
                    setInitialLoadError(null);
                    setHasFetched(true);
                    void refreshUserDetailsForSyncState(persisted);
                }

                await fetchAndStoreLockerData(mk);
                if (canApplyState()) {
                    setHasFetched(true);
                }
            } catch (error) {
                log.error("Failed to fetch locker data", error);
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
    }, [fetchAndStoreLockerData, logout, router, showMiniDialog]);

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
    };
};
