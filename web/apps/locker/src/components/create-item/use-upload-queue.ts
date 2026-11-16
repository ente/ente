import {
    formatLockerMutationError,
    lockerUpgradeCTAType,
    type LockerUpgradeCTAType,
} from "@/services/locker-errors";
import {
    exceedsPaidLockerHardLimit,
    validateLockerUploadBatch,
    type LockerUploadLimitState,
    type LockerUploadPreflightFailure,
} from "@/services/locker-limits";
import type { LockerUploadProgress } from "@/services/uploads";
import type { LockerCollection, LockerUploadCandidate } from "@/types";
import log from "ente-base/log";
import { t } from "i18next";
import {
    useCallback,
    useRef,
    useState,
    type Dispatch,
    type SetStateAction,
} from "react";
import {
    dedupeCollectionNames,
    fileForUpload,
    filterNonEmptyUploadItems,
    normalizeCollectionName,
    replaceCreatedUploadDestination,
    uploadQueueItemKey,
    type UploadDestinationsByFileKey,
} from "./file-upload-helpers";

const MAX_PARALLEL_UPLOADS = 4;

export interface LockerUploadCallbacks {
    onUploadProgress?: (
        file: File,
        collectionIDs: number[],
        onProgress: (progress: LockerUploadProgress) => void,
    ) => Promise<void>;
    onUploadItemComplete?: () => void;
    onUploadsFinished?: (
        uploadedCount: number,
        selectedFileCount: number,
    ) => Promise<void>;
    onCreateUploadCollection?: (name: string) => Promise<number>;
    onRefreshUploadCollections?: () => Promise<LockerCollection[] | undefined>;
    onEnsureUploadLimitState?: () => Promise<
        { userDetails: LockerUploadLimitState } | undefined
    >;
}

interface UseUploadQueueProps extends LockerUploadCallbacks {
    eligibleCollections: LockerCollection[];
    selectedUploadItems: LockerUploadCandidate[];
    uploadDestinations: UploadDestinationsByFileKey;
    setUploadDestinations: Dispatch<
        SetStateAction<UploadDestinationsByFileKey>
    >;
    userDetails?: LockerUploadLimitState;
    setError: Dispatch<SetStateAction<string | null>>;
    setUpgradeCTAType: Dispatch<SetStateAction<LockerUpgradeCTAType | null>>;
}

interface UploadState {
    completedFileKeys: Set<string>;
    failedFileKeys: Set<string>;
    uploadingFileKeys: Set<string>;
    uploadProgressByFileKey: Record<string, LockerUploadProgress | null>;
    uploadCapByFileKey: Record<string, number>;
}

const emptyUploadState = (): UploadState => ({
    completedFileKeys: new Set(),
    failedFileKeys: new Set(),
    uploadingFileKeys: new Set(),
    uploadProgressByFileKey: {},
    uploadCapByFileKey: {},
});

export function useUploadQueue({
    eligibleCollections,
    selectedUploadItems,
    uploadDestinations,
    setUploadDestinations,
    userDetails,
    setError,
    setUpgradeCTAType,
    onUploadProgress,
    onUploadItemComplete,
    onUploadsFinished,
    onCreateUploadCollection,
    onRefreshUploadCollections,
    onEnsureUploadLimitState,
}: UseUploadQueueProps) {
    const uploadInFlight = useRef(false);
    const [uploading, setUploading] = useState(false);
    const [completedFileKeys, setCompletedFileKeys] = useState<Set<string>>(
        () => new Set(),
    );
    const [failedFileKeys, setFailedFileKeys] = useState<Set<string>>(
        () => new Set(),
    );
    const [uploadingFileKeys, setUploadingFileKeys] = useState<Set<string>>(
        () => new Set(),
    );
    const [uploadProgressByFileKey, setUploadProgressByFileKey] = useState<
        Record<string, LockerUploadProgress | null>
    >({});
    const [uploadCapByFileKey, setUploadCapByFileKey] = useState<
        Record<string, number>
    >({});

    const resetUploadState = useCallback(() => {
        const nextState = emptyUploadState();
        setCompletedFileKeys(nextState.completedFileKeys);
        setFailedFileKeys(nextState.failedFileKeys);
        setUploadingFileKeys(nextState.uploadingFileKeys);
        setUploadProgressByFileKey(nextState.uploadProgressByFileKey);
        setUploadCapByFileKey(nextState.uploadCapByFileKey);
    }, []);

    const upload = useCallback(
        async (onComplete: () => void) => {
            if (
                uploadInFlight.current ||
                !selectedUploadItems.length ||
                !onUploadProgress
            ) {
                return;
            }

            const pendingUploadItems = filterNonEmptyUploadItems(
                selectedUploadItems.filter(
                    (item) => !completedFileKeys.has(uploadQueueItemKey(item)),
                ),
            );
            if (pendingUploadItems.length === 0) {
                return;
            }

            uploadInFlight.current = true;
            setUploading(true);
            try {
                let effectiveUserDetails = userDetails;
                if (!effectiveUserDetails) {
                    const uploadLimitState = await onEnsureUploadLimitState?.();
                    effectiveUserDetails = uploadLimitState?.userDetails;
                }

                if (!effectiveUserDetails) {
                    setError(t("generic_error_retry"));
                    setUpgradeCTAType(null);
                    return;
                }

                const preflightFailure = validateLockerUploadBatch(
                    pendingUploadItems.map(({ file }) => file),
                    effectiveUserDetails,
                );
                if (preflightFailure) {
                    const hitsPaidHardCap = exceedsPaidLockerHardLimit(
                        pendingUploadItems.map(({ file }) => file),
                        effectiveUserDetails,
                    );
                    const preflightFailureMessage = (
                        failure: LockerUploadPreflightFailure,
                    ) => {
                        if (
                            hitsPaidHardCap &&
                            (failure.reason === "fileCountLimit" ||
                                failure.reason === "storageLimit")
                        ) {
                            return t("uploadLockerHardCapErrorBody");
                        }
                        switch (failure.reason) {
                            case "fileCountLimit":
                                return t("uploadFileCountLimitErrorBody");
                            case "fileTooLarge":
                                return t("uploadFileTooLargeErrorBody");
                            case "storageLimit":
                                return t("uploadStorageLimitErrorBody");
                        }
                    };

                    setError(preflightFailureMessage(preflightFailure));
                    setUpgradeCTAType(
                        hitsPaidHardCap
                            ? null
                            : preflightFailure.reason === "fileCountLimit"
                              ? "fileCountLimit"
                              : preflightFailure.reason === "storageLimit"
                                ? "storageLimit"
                                : null,
                    );
                    return;
                }

                const destinationsByItem = pendingUploadItems.map((item) => {
                    const fileKey = uploadQueueItemKey(item);
                    return {
                        item,
                        fileKey,
                        destinations: uploadDestinations[fileKey] ?? [],
                    };
                });
                let collections = eligibleCollections;
                let eligibleIDs = new Set(collections.map(({ id }) => id));
                const hasUnsyncedDestination = destinationsByItem.some(
                    ({ destinations }) =>
                        destinations.some(
                            (destination) =>
                                destination.kind === "existing" &&
                                !eligibleIDs.has(destination.id),
                        ),
                );
                if (hasUnsyncedDestination && onRefreshUploadCollections) {
                    const refreshed = await onRefreshUploadCollections();
                    if (!refreshed) {
                        setError(t("generic_error_retry"));
                        setUpgradeCTAType(null);
                        return;
                    }
                    collections = refreshed;
                    eligibleIDs = new Set(collections.map(({ id }) => id));
                }
                const existingNames = new Set(
                    collections.map(({ name }) =>
                        normalizeCollectionName(name),
                    ),
                );
                const newNames: string[] = [];

                for (const { destinations } of destinationsByItem) {
                    for (const destination of destinations) {
                        if (destination.kind === "existing") {
                            if (!eligibleIDs.has(destination.id)) {
                                setError(t("uploadDestinationUnavailable"));
                                setUpgradeCTAType(null);
                                return;
                            }
                        } else if (
                            destination.kind === "ambiguous" ||
                            existingNames.has(
                                normalizeCollectionName(destination.name),
                            )
                        ) {
                            setError(
                                t("uploadDestinationNeedsChoice", {
                                    name: destination.name,
                                }),
                            );
                            setUpgradeCTAType(null);
                            return;
                        } else {
                            newNames.push(destination.name);
                        }
                    }
                }

                setError(null);
                setUpgradeCTAType(null);
                const pendingUploadFileKeys = new Set(
                    pendingUploadItems.map((item) => uploadQueueItemKey(item)),
                );
                setFailedFileKeys((current) => {
                    const next = new Set(current);
                    pendingUploadFileKeys.forEach((fileKey) =>
                        next.delete(fileKey),
                    );
                    return next;
                });
                setUploadingFileKeys((current) => {
                    const next = new Set(current);
                    pendingUploadFileKeys.forEach((fileKey) =>
                        next.delete(fileKey),
                    );
                    return next;
                });
                setUploadProgressByFileKey((current) =>
                    Object.fromEntries(
                        Object.entries(current).filter(
                            ([fileKey]) => !pendingUploadFileKeys.has(fileKey),
                        ),
                    ),
                );
                setUploadCapByFileKey((current) =>
                    Object.fromEntries(
                        Object.entries(current).filter(
                            ([fileKey]) => !pendingUploadFileKeys.has(fileKey),
                        ),
                    ),
                );

                const createdIDs = new Map<string, number>();
                let refreshedCollections: LockerCollection[] | undefined;
                try {
                    for (const name of dedupeCollectionNames(newNames)) {
                        if (!onCreateUploadCollection)
                            throw new Error(
                                "Collection creation is unavailable",
                            );
                        const id = await onCreateUploadCollection(name);
                        createdIDs.set(normalizeCollectionName(name), id);
                        setUploadDestinations((current) =>
                            replaceCreatedUploadDestination(current, name, id),
                        );
                    }
                } finally {
                    if (createdIDs.size > 0) {
                        refreshedCollections =
                            await onRefreshUploadCollections?.();
                    }
                }

                if (createdIDs.size > 0) {
                    const refreshedIDs = new Set(
                        refreshedCollections?.map(({ id }) => id),
                    );
                    if (
                        [...createdIDs.values()].some(
                            (id) => !refreshedIDs.has(id),
                        )
                    ) {
                        setError(t("generic_error_retry"));
                        return;
                    }
                }

                const uploadTargets = destinationsByItem.map(
                    ({ item, fileKey, destinations }) => ({
                        item,
                        fileKey,
                        collectionIDs: [
                            ...new Set(
                                destinations.map((destination) => {
                                    if (destination.kind === "existing")
                                        return destination.id;
                                    const id = createdIDs.get(
                                        normalizeCollectionName(
                                            destination.name,
                                        ),
                                    );
                                    if (id === undefined)
                                        throw new Error(
                                            "Upload destination was not resolved",
                                        );
                                    return id;
                                }),
                            ),
                        ],
                    }),
                );

                let uploadedCount = 0;
                let nextIndex = 0;
                const worker = async () => {
                    while (true) {
                        const target = uploadTargets[nextIndex];
                        nextIndex += 1;
                        if (!target) {
                            return;
                        }

                        const { item, fileKey, collectionIDs } = target;
                        setUploadingFileKeys((current) =>
                            new Set(current).add(fileKey),
                        );
                        setUploadCapByFileKey((current) => ({
                            ...current,
                            [fileKey]: 90 + Math.floor(Math.random() * 10),
                        }));
                        setUploadProgressByFileKey((current) => ({
                            ...current,
                            [fileKey]: { phase: "preparing" },
                        }));

                        try {
                            await onUploadProgress(
                                fileForUpload(item),
                                collectionIDs,
                                (progress) => {
                                    setUploadProgressByFileKey((current) => ({
                                        ...current,
                                        [fileKey]: progress,
                                    }));
                                },
                            );
                            uploadedCount += 1;
                            setCompletedFileKeys((current) =>
                                new Set(current).add(fileKey),
                            );
                            setFailedFileKeys((current) => {
                                const next = new Set(current);
                                next.delete(fileKey);
                                return next;
                            });
                            onUploadItemComplete?.();
                        } catch (error) {
                            log.error("Failed to upload Locker file", error);
                            const formattedError =
                                await formatLockerMutationError(
                                    error,
                                    "uploadFile",
                                );
                            const nextUpgradeCTAType =
                                await lockerUpgradeCTAType(error);
                            setError((current) => current ?? formattedError);
                            if (nextUpgradeCTAType) {
                                setUpgradeCTAType(
                                    (current) => current ?? nextUpgradeCTAType,
                                );
                            }
                            setFailedFileKeys((current) =>
                                new Set(current).add(fileKey),
                            );
                        } finally {
                            setUploadingFileKeys((current) => {
                                const next = new Set(current);
                                next.delete(fileKey);
                                return next;
                            });
                        }
                    }
                };

                await Promise.all(
                    Array.from({
                        length: Math.min(
                            MAX_PARALLEL_UPLOADS,
                            pendingUploadItems.length,
                        ),
                    }).map(() => worker()),
                );

                if (uploadedCount > 0) {
                    await onUploadsFinished?.(
                        uploadedCount,
                        selectedUploadItems.length,
                    );
                }
                if (
                    completedFileKeys.size + uploadedCount ===
                    selectedUploadItems.length
                ) {
                    onComplete();
                }
            } catch (error) {
                log.error("Failed to upload Locker files", error);
                setError(await formatLockerMutationError(error, "uploadFile"));
                setUpgradeCTAType(await lockerUpgradeCTAType(error));
            } finally {
                uploadInFlight.current = false;
                setUploading(false);
            }
        },
        [
            completedFileKeys,
            eligibleCollections,
            onCreateUploadCollection,
            onRefreshUploadCollections,
            onEnsureUploadLimitState,
            onUploadItemComplete,
            onUploadProgress,
            onUploadsFinished,
            uploadDestinations,
            selectedUploadItems,
            userDetails,
            setError,
            setUploadDestinations,
            setUpgradeCTAType,
        ],
    );

    return {
        uploading,
        completedFileKeys,
        failedFileKeys,
        uploadingFileKeys,
        uploadProgressByFileKey,
        uploadCapByFileKey,
        resetUploadState,
        upload,
    };
}
