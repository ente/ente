export const LOCKER_FILE_LIMIT_FREE = 100;
export const LOCKER_FILE_LIMIT_PAID = 1000;
export const LOCKER_STORAGE_LIMIT_PAID_BYTES = 10 * 1024 * 1024 * 1024;
export const LOCKER_MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024 * 1024;

export interface LockerUploadLimitState {
    usage: number;
    storageLimit: number;
    fileCount: number;
    lockerFileLimit: number;
    isPartOfFamily: boolean;
    lockerFamilyFileCount?: number;
}

interface LockerUploadAllowance {
    maxFileCount: number;
    currentFileCount: number;
    remainingFileCount: number;
    freeStorage: number;
}

type LockerUploadPreflightFailureReason =
    | "fileCountLimit"
    | "fileTooLarge"
    | "storageLimit";

export interface LockerUploadPreflightFailure {
    reason: LockerUploadPreflightFailureReason;
    fileName?: string;
}

export const lockerUploadAllowance = (
    userDetails: LockerUploadLimitState,
): LockerUploadAllowance => {
    const maxFileCount = Math.max(userDetails.lockerFileLimit, 1);
    const currentFileCount =
        userDetails.isPartOfFamily &&
        typeof userDetails.lockerFamilyFileCount === "number"
            ? userDetails.lockerFamilyFileCount
            : userDetails.fileCount;

    return {
        maxFileCount,
        currentFileCount,
        remainingFileCount: Math.max(maxFileCount - currentFileCount, 0),
        freeStorage: Math.max(userDetails.storageLimit - userDetails.usage, 0),
    };
};

export const exceedsPaidLockerHardLimit = (
    files: File[],
    userDetails: LockerUploadLimitState,
) => {
    const allowance = lockerUploadAllowance(userDetails);
    const totalUploadSize = files.reduce((total, file) => total + file.size, 0);

    return (
        allowance.currentFileCount + files.length > LOCKER_FILE_LIMIT_PAID ||
        userDetails.usage + totalUploadSize > LOCKER_STORAGE_LIMIT_PAID_BYTES
    );
};

export const validateLockerUploadBatch = (
    files: File[],
    userDetails: LockerUploadLimitState | undefined,
): LockerUploadPreflightFailure | null => {
    const oversizedFile = files.find(
        (file) => file.size > LOCKER_MAX_FILE_SIZE_BYTES,
    );
    if (oversizedFile) {
        return { reason: "fileTooLarge", fileName: oversizedFile.name };
    }

    if (!userDetails) {
        return null;
    }

    const allowance = lockerUploadAllowance(userDetails);
    if (files.length > allowance.remainingFileCount) {
        return { reason: "fileCountLimit" };
    }

    const totalUploadSize = files.reduce((total, file) => total + file.size, 0);
    if (totalUploadSize > allowance.freeStorage) {
        return { reason: "storageLimit" };
    }

    return null;
};
