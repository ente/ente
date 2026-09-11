import {
    formatLockerMutationError,
    lockerUpgradeCTAType,
    type LockerUpgradeCTAType,
} from "@/services/locker-errors";
import type { LockerUploadLimitState } from "@/services/locker-limits";
import type {
    LockerCollection,
    LockerItemType,
    LockerUploadCandidate,
} from "@/types";
import {
    isCollectionOwner,
    isUncategorizedCollection,
    sortLockerCollections,
} from "@/types";
import { savedLocalUser } from "ente-accounts/services/accounts-db";
import log from "ente-base/log";
import { t } from "i18next";
import type { ChangeEvent } from "react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
    collectionNamesByUploadItem,
    filterNonEmptyUploadItems,
    uploadQueueItemKey,
} from "./file-upload-helpers";
import { getRequiredFields } from "./item-form-fields-utils";
import { useUploadQueue, type LockerUploadCallbacks } from "./use-upload-queue";

export type CreateOption = LockerItemType;

export interface CreateItemDialogEditItem {
    id: number;
    type: LockerItemType;
    data: Record<string, unknown>;
    collectionID: number;
    collectionIDs: number[];
}

interface UseCreateItemDialogStateProps extends LockerUploadCallbacks {
    open: boolean;
    collections: LockerCollection[];
    onClose: () => void;
    onSave: (
        type: LockerItemType,
        data: Record<string, unknown>,
        collectionIDs: number[],
    ) => Promise<void>;
    defaultCollectionID?: number | null;
    initialItems?: LockerUploadCandidate[];
    editItem?: CreateItemDialogEditItem | null;
    userDetails?: LockerUploadLimitState;
}

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
        const ownedVisibleCollections = sortLockerCollections(
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
    const {
        uploading,
        completedFileKeys,
        failedFileKeys,
        uploadingFileKeys,
        uploadProgressByFileKey,
        uploadCapByFileKey,
        resetUploadState,
        upload,
    } = useUploadQueue({
        displayCollections,
        selectedUploadItems,
        selectedCollectionNamesByFileKey,
        userDetails,
        setError,
        setUpgradeCTAType,
        onUploadProgress,
        onUploadItemComplete,
        onUploadsFinished,
        onEnsureCollections,
        onEnsureUploadLimitState,
    });

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

    const handleUpload = useCallback(
        () => upload(handleClose),
        [upload, handleClose],
    );

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
        handleStepBackToOptions,
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
