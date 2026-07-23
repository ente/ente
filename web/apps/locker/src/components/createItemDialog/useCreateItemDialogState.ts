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
import type { LockerUploadProgress } from "@/services/remote";
import type {
    LockerCollection,
    LockerItemType,
    LockerUploadCandidate,
} from "@/types";
import {
    isCollectionOwner,
    isUncategorizedCollection,
    visibleLockerCollections,
} from "@/types";
import { savedLocalUser } from "ente-accounts-rs/services/accounts-db";
import log from "ente-base/log";
import { t } from "i18next";
import type { ChangeEvent } from "react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
    collectionNamesByUploadItem,
    dedupeCollectionNames,
    filterNonEmptyUploadItems,
    normalizeCollectionName,
    uploadQueueItemKey,
} from "./fileUploadHelpers";
import { getRequiredFields } from "./itemFormFieldsUtils";

export type CreateOption = LockerItemType;
const MAX_PARALLEL_UPLOADS = 4;

export interface CreateItemDialogEditItem {
    id: number;
    type: LockerItemType;
    data: Record<string, unknown>;
    collectionID: number;
    collectionIDs: number[];
}

interface UseCreateItemDialogStateProps {
    open: boolean;
    collections: LockerCollection[];
    onClose: () => void;
    onSave: (
        type: LockerItemType,
        data: Record<string, unknown>,
        collectionIDs: number[],
    ) => Promise<void>;
    onUploadProgress?: (
        file: File,
        collectionIDs: number[],
        onProgress: (progress: LockerUploadProgress) => void,
    ) => Promise<void>;
    onUploadItemComplete?: () => void;
    onUploadsFinished?: (uploadedCount: number) => Promise<void>;
    onEnsureCollections?: (
        names: string[],
    ) => Promise<Map<string, number> | Record<string, number>>;
    onEnsureUploadLimitState?: () => Promise<
        { userDetails: LockerUploadLimitState } | undefined
    >;
    defaultCollectionID?: number | null;
    initialItems?: LockerUploadCandidate[];
    editItem?: CreateItemDialogEditItem | null;
    userDetails?: LockerUploadLimitState;
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

const initialEditCollectionIDs = (
    editItem: CreateItemDialogEditItem | null | undefined,
) => {
    if (!editItem) {
        return [];
    }
    if (editItem.collectionIDs.length > 0) {
        return editItem.collectionIDs;
    }
    return editItem.collectionID ? [editItem.collectionID] : [];
};

const editFormData = (
    editItem: CreateItemDialogEditItem | null | undefined,
): Record<string, string> =>
    editItem
        ? Object.fromEntries(
              Object.entries(editItem.data).filter(
                  (entry): entry is [string, string] =>
                      typeof entry[1] === "string",
              ),
          )
        : {};

export const useCreateItemDialogState = ({
    open,
    collections,
    onClose,
    onSave,
    onUploadProgress,
    onUploadItemComplete,
    onUploadsFinished,
    onEnsureCollections,
    onEnsureUploadLimitState,
    defaultCollectionID,
    initialItems,
    editItem,
    userDetails,
}: UseCreateItemDialogStateProps) => {
    const isEditMode = !!editItem;
    const currentUserID = savedLocalUser()?.id;
    const editCollectionIDs = useMemo(
        () => initialEditCollectionIDs(editItem),
        [editItem],
    );
    const displayCollections = useMemo(() => {
        const ownedVisibleCollections = visibleLockerCollections(
            collections,
        ).filter(
            (collection) =>
                currentUserID !== undefined &&
                isCollectionOwner(collection, currentUserID),
        );

        if (!isEditMode) {
            return ownedVisibleCollections.filter(
                (collection) => !isUncategorizedCollection(collection),
            );
        }

        const visibleCollectionIDSet = new Set(
            ownedVisibleCollections.map((collection) => collection.id),
        );
        const currentEditCollections = collections.filter(
            (collection) =>
                editCollectionIDs.includes(collection.id) &&
                !visibleCollectionIDSet.has(collection.id),
        );

        return [...ownedVisibleCollections, ...currentEditCollections];
    }, [collections, currentUserID, editCollectionIDs, isEditMode]);

    const [selectedOption, setSelectedOption] = useState<CreateOption | null>(
        editItem?.type ?? (initialItems?.length ? "file" : null),
    );
    const [selectedCollectionIDs, setSelectedCollectionIDs] =
        useState<number[]>(editCollectionIDs);
    const [saving, setSaving] = useState(false);
    const [uploading, setUploading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [upgradeCTAType, setUpgradeCTAType] =
        useState<LockerUpgradeCTAType | null>(null);
    const [formData, setFormData] = useState<Record<string, string>>(
        editFormData(editItem),
    );
    const [showPassword, setShowPassword] = useState(false);
    const [selectedUploadItems, setSelectedUploadItems] = useState<
        LockerUploadCandidate[]
    >(filterNonEmptyUploadItems(initialItems ?? []));
    const [
        selectedCollectionNamesByFileKey,
        setSelectedCollectionNamesByFileKey,
    ] = useState<Record<string, string[]>>({});
    const [customCollectionNames, setCustomCollectionNames] = useState<
        string[]
    >([]);
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

    const isFileMode = selectedOption === "file";
    const editCollectionID = editItem?.collectionID ?? null;
    const selectedType =
        selectedOption && selectedOption !== "file"
            ? (selectedOption as LockerItemType)
            : null;
    const formType =
        isEditMode && selectedOption === "file" ? "file" : selectedType;
    const displayCollectionsRef = useRef(displayCollections);

    displayCollectionsRef.current = displayCollections;

    const normalizeSelectedCollectionIDs = useCallback(
        (collectionIDs: number[]) =>
            collectionIDs.filter((collectionID) =>
                displayCollectionsRef.current.some(
                    (collection) => collection.id === collectionID,
                ),
            ),
        [],
    );

    const resetUploadState = useCallback(() => {
        const nextState = emptyUploadState();
        setCompletedFileKeys(nextState.completedFileKeys);
        setFailedFileKeys(nextState.failedFileKeys);
        setUploadingFileKeys(nextState.uploadingFileKeys);
        setUploadProgressByFileKey(nextState.uploadProgressByFileKey);
        setUploadCapByFileKey(nextState.uploadCapByFileKey);
    }, []);

    useEffect(() => {
        if (!open) {
            return;
        }

        setSelectedOption(
            editItem?.type ?? (initialItems?.length ? "file" : null),
        );
        const defaultCollectionName =
            defaultCollectionID !== null && defaultCollectionID !== undefined
                ? displayCollectionsRef.current.find(
                      (collection) => collection.id === defaultCollectionID,
                  )?.name
                : undefined;
        setSelectedCollectionIDs(
            isEditMode
                ? normalizeSelectedCollectionIDs(
                      editCollectionIDs.length > 0
                          ? editCollectionIDs
                          : editCollectionID
                            ? [editCollectionID]
                            : [],
                  )
                : normalizeSelectedCollectionIDs(
                      defaultCollectionID !== null &&
                          defaultCollectionID !== undefined
                          ? [defaultCollectionID]
                          : [],
                  ),
        );
        setFormData(editFormData(editItem));
        setShowPassword(false);
        const filteredInitialItems = filterNonEmptyUploadItems(
            initialItems ?? [],
        );
        setSelectedUploadItems(filteredInitialItems);
        setCustomCollectionNames([]);
        setSelectedCollectionNamesByFileKey(
            collectionNamesByUploadItem(
                filteredInitialItems,
                defaultCollectionName,
            ),
        );
        resetUploadState();
        setError(null);
        setUpgradeCTAType(null);
    }, [
        defaultCollectionID,
        editCollectionID,
        editCollectionIDs,
        editItem,
        initialItems,
        isEditMode,
        normalizeSelectedCollectionIDs,
        open,
        resetUploadState,
    ]);

    useEffect(() => {
        if (
            !open ||
            isEditMode ||
            selectedCollectionIDs.every((selectedCollectionID) =>
                displayCollections.some(
                    (collection) => collection.id === selectedCollectionID,
                ),
            )
        ) {
            return;
        }

        setSelectedCollectionIDs((current) =>
            current.filter((selectedCollectionID) =>
                displayCollections.some(
                    (collection) => collection.id === selectedCollectionID,
                ),
            ),
        );
    }, [displayCollections, isEditMode, open, selectedCollectionIDs]);

    useEffect(() => {
        if (
            !open ||
            isEditMode ||
            selectedCollectionIDs.length > 0 ||
            defaultCollectionID === null ||
            defaultCollectionID === undefined ||
            !displayCollections.some(
                (collection) => collection.id === defaultCollectionID,
            )
        ) {
            return;
        }

        setSelectedCollectionIDs([defaultCollectionID]);
    }, [
        defaultCollectionID,
        displayCollections,
        isEditMode,
        open,
        selectedCollectionIDs.length,
    ]);

    const handleClose = useCallback(() => {
        if (saving || uploading) {
            return;
        }

        onClose();
    }, [onClose, saving, uploading]);

    const handleStepBackToOptions = useCallback(() => {
        if (isEditMode || saving || uploading) {
            return;
        }

        setSelectedOption(null);
        setFormData({});
        setShowPassword(false);
        setError(null);
        setUpgradeCTAType(null);
    }, [isEditMode, saving, uploading]);

    const handleDialogClose = useCallback(
        (_event: object, reason?: "backdropClick" | "escapeKeyDown") => {
            if (
                reason === "escapeKeyDown" &&
                selectedType !== null &&
                !isEditMode
            ) {
                handleStepBackToOptions();
                return;
            }

            handleClose();
        },
        [handleClose, handleStepBackToOptions, isEditMode, selectedType],
    );

    const handleSelectOption = useCallback(
        (option: CreateOption) => {
            setSelectedOption(option);
            setFormData({});
            setSelectedUploadItems([]);
            setCustomCollectionNames([]);
            setSelectedCollectionNamesByFileKey({});
            resetUploadState();
            setError(null);
            setUpgradeCTAType(null);
        },
        [resetUploadState],
    );

    const handleFieldChange = useCallback((field: string, value: string) => {
        setFormData((previous) => ({ ...previous, [field]: value }));
        setError(null);
        setUpgradeCTAType(null);
    }, []);

    const handleFileSelect = useCallback(
        (event: ChangeEvent<HTMLInputElement>) => {
            const files = Array.from(event.target.files ?? []);
            if (files.length === 0) {
                return;
            }

            const defaultCollectionName =
                selectedCollectionIDs.length > 0
                    ? displayCollectionsRef.current.find((collection) =>
                          selectedCollectionIDs.includes(collection.id),
                      )?.name
                    : undefined;
            const items = files.map((file) => ({
                file,
                relativePath: file.webkitRelativePath || file.name,
                suggestedCollectionNames: [],
            }));
            const nonEmptyItems = filterNonEmptyUploadItems(items);
            setSelectedUploadItems(nonEmptyItems);
            setCustomCollectionNames([]);
            setSelectedCollectionNamesByFileKey(
                collectionNamesByUploadItem(
                    nonEmptyItems,
                    defaultCollectionName,
                ),
            );
            resetUploadState();
            setError(null);
            setUpgradeCTAType(null);
        },
        [resetUploadState, selectedCollectionIDs],
    );

    const handleSave = useCallback(async () => {
        if (!formType) {
            return;
        }

        for (const field of getRequiredFields(formType)) {
            const value = formData[field];
            if (typeof value !== "string" || !value.trim()) {
                setError(t("required_field"));
                return;
            }
        }

        setSaving(true);
        setError(null);
        setUpgradeCTAType(null);
        try {
            const cleanData = Object.fromEntries(
                Object.entries(formData)
                    .filter(
                        ([, value]) =>
                            typeof value === "string" && value.trim(),
                    )
                    .map(([key, value]) => [key, value.trim()]),
            );
            await onSave(formType, cleanData, selectedCollectionIDs);
            handleClose();
        } catch (error) {
            log.error("Failed to save Locker item", error);
            setError(await formatLockerMutationError(error, "createItem"));
            setUpgradeCTAType(await lockerUpgradeCTAType(error));
        } finally {
            setSaving(false);
        }
    }, [formData, formType, handleClose, onSave, selectedCollectionIDs]);

    const handleUpload = useCallback(async () => {
        if (selectedUploadItems.length === 0 || !onUploadProgress) {
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

        setUploading(true);
        setError(null);
        setUpgradeCTAType(null);
        const pendingUploadFileKeys = new Set(
            pendingUploadItems.map((item) => uploadQueueItemKey(item)),
        );
        setFailedFileKeys((current) => {
            const next = new Set(current);
            pendingUploadFileKeys.forEach((fileKey) => next.delete(fileKey));
            return next;
        });
        setUploadingFileKeys((current) => {
            const next = new Set(current);
            pendingUploadFileKeys.forEach((fileKey) => next.delete(fileKey));
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
        let uploadedCount = 0;
        try {
            const existingNormalizedNameToID = new Map(
                displayCollections.map((collection) => [
                    normalizeCollectionName(collection.name),
                    collection.id,
                ]),
            );
            const normalizedNameToIDResult = await onEnsureCollections?.(
                dedupeCollectionNames(
                    Object.values(selectedCollectionNamesByFileKey).flat(),
                ),
            );
            const normalizedNameToID = new Map(existingNormalizedNameToID);
            if (normalizedNameToIDResult instanceof Map) {
                for (const [name, id] of normalizedNameToIDResult.entries()) {
                    normalizedNameToID.set(normalizeCollectionName(name), id);
                }
            } else {
                for (const [name, id] of Object.entries(
                    normalizedNameToIDResult ?? {},
                )) {
                    normalizedNameToID.set(normalizeCollectionName(name), id);
                }
            }
            const uploadTargets = pendingUploadItems.map((item) => {
                const fileKey = uploadQueueItemKey(item);
                const collectionIDs = dedupeCollectionNames(
                    selectedCollectionNamesByFileKey[fileKey] ?? [],
                )
                    .map((name) =>
                        normalizedNameToID.get(normalizeCollectionName(name)),
                    )
                    .filter((id): id is number => typeof id === "number");
                return { item, fileKey, collectionIDs };
            });

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
                            item.file,
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
                        const formattedError = await formatLockerMutationError(
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
                await onUploadsFinished?.(uploadedCount);
            }
            if (
                completedFileKeys.size + uploadedCount ===
                selectedUploadItems.length
            ) {
                handleClose();
            }
        } catch (error) {
            log.error("Failed to upload Locker files", error);
            setError(await formatLockerMutationError(error, "uploadFile"));
            setUpgradeCTAType(await lockerUpgradeCTAType(error));
        } finally {
            setUploading(false);
        }
    }, [
        completedFileKeys,
        displayCollections,
        handleClose,
        onEnsureCollections,
        onEnsureUploadLimitState,
        onUploadItemComplete,
        onUploadProgress,
        onUploadsFinished,
        selectedCollectionNamesByFileKey,
        selectedUploadItems,
        userDetails,
    ]);

    const canSave =
        formType !== null &&
        getRequiredFields(formType).every(
            (field) =>
                typeof formData[field] === "string" && formData[field].trim(),
        );
    const canUpload =
        isFileMode &&
        selectedUploadItems.length > 0 &&
        selectedUploadItems.some(
            (item) => !completedFileKeys.has(uploadQueueItemKey(item)),
        );
    const savedUploadCount = completedFileKeys.size;
    const totalUploadCount = selectedUploadItems.length;
    const showUploadCounter = isFileMode && totalUploadCount > 0;
    const shouldShowDialogErrorCard =
        !!error && (isFileMode || upgradeCTAType === "fileCountLimit");

    return {
        canSave,
        canUpload,
        completedFileKeys,
        customCollectionNames,
        displayCollections,
        error,
        formData,
        formType,
        handleClose,
        handleDialogClose,
        handleFieldChange,
        handleFileSelect,
        handleSave,
        handleSelectOption,
        handleUpload,
        isEditMode,
        isFileMode,
        saving,
        savedUploadCount,
        selectedCollectionIDs,
        selectedCollectionNamesByFileKey,
        selectedOption,
        selectedType,
        selectedUploadItems,
        setCustomCollectionNames,
        setSelectedCollectionIDs,
        setSelectedCollectionNamesByFileKey,
        setSelectedUploadItems,
        setShowPassword,
        shouldShowDialogErrorCard,
        showPassword,
        showUploadCounter,
        totalUploadCount,
        upgradeCTAType,
        uploading,
        uploadingFileKeys,
        uploadCapByFileKey,
        uploadProgressByFileKey,
        failedFileKeys,
    };
};
