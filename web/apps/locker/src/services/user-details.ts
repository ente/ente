import { savedLocalUser } from "ente-accounts/services/accounts-db";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import {
    LOCKER_FILE_LIMIT_FREE,
    LOCKER_FILE_LIMIT_PAID,
} from "./locker-limits";

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

export const loadLockerUsage = async (
    headers?: Awaited<ReturnType<typeof authenticatedRequestHeaders>>,
) => {
    const requestHeaders = headers ?? (await authenticatedRequestHeaders());
    const lockerUsageRes = await fetch(await apiURL("/users/locker-usage"), {
        headers: requestHeaders,
    });
    ensureOk(lockerUsageRes);
    const lockerUsage = (await lockerUsageRes.json()) as LockerUsageResponse;

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
};

export const loadUserEmail = async (
    headers?: Awaited<ReturnType<typeof authenticatedRequestHeaders>>,
) => {
    const requestHeaders = headers ?? (await authenticatedRequestHeaders());
    const userProfileRes = await fetch(
        await apiURL("/users/details/v2", { memoryCount: false }),
        { headers: requestHeaders },
    );
    ensureOk(userProfileRes);
    const userProfile =
        (await userProfileRes.json()) as LockerUserProfileResponse;
    return userProfile.email ?? savedLocalUser()?.email ?? "";
};
