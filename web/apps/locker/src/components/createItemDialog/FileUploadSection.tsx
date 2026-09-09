import { CollectionChipRow } from "@/components/createItemDialog/CollectionChipRow";
import {
    lockerPrimaryButtonSx,
    lockerScrollAreaSx,
} from "@/components/createItemDialog/create-item-dialog-styles";
import { CreateCollectionRow } from "@/components/createItemDialog/CreateCollectionRow";
import { lockerItemIcon } from "@/components/locker-item-icons";
import type { LockerUploadProgress } from "@/services/remote";
import type { LockerCollection, LockerUploadCandidate } from "@/types";
import { Cancel01Icon, FileUploadIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import CheckRoundedIcon from "@mui/icons-material/CheckRounded";
import ErrorOutlineRoundedIcon from "@mui/icons-material/ErrorOutlineRounded";
import ScheduleRoundedIcon from "@mui/icons-material/ScheduleRounded";
import {
    Box,
    ButtonBase,
    CircularProgress,
    IconButton,
    LinearProgress,
    Stack,
    Typography,
} from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { t } from "i18next";
import React, {
    useCallback,
    useEffect,
    useLayoutEffect,
    useMemo,
    useRef,
    useState,
} from "react";

import {
    addCollectionName,
    dedupeCollectionNames,
    formatFileSize,
    normalizeCollectionName,
    toggleCollectionName,
    uploadItemParentPath,
    uploadProgressValue,
    uploadQueueItemKey,
} from "./file-upload-helpers";

interface FileUploadSectionProps {
    fileInputRef: React.RefObject<HTMLInputElement | null>;
    selectedUploadItems: LockerUploadCandidate[];
    collections: LockerCollection[];
    availableCollectionNames: string[];
    selectedCollectionNamesByFileKey: Record<string, string[]>;
    completedFileKeys: Set<string>;
    failedFileKeys: Set<string>;
    uploadingFileKeys: Set<string>;
    uploadProgressByFileKey: Record<string, LockerUploadProgress | null>;
    uploadCapByFileKey: Record<string, number>;
    uploading: boolean;
    canUpload: boolean;
    onFileSelect: (event: React.ChangeEvent<HTMLInputElement>) => void;
    onToggleCollectionName: (fileKey: string, name: string) => void;
    onAddCollectionName: (fileKey: string, name: string) => void;
    onAddAvailableCollectionName: (name: string) => void;
    onSetCollectionNamesForAllItems: (names: string[]) => void;
    onRemoveItem: (fileKey: string) => void;
    onUpload: () => Promise<void>;
}

export function FileUploadSection({
    fileInputRef,
    selectedUploadItems,
    collections,
    availableCollectionNames,
    selectedCollectionNamesByFileKey,
    completedFileKeys,
    failedFileKeys,
    uploadingFileKeys,
    uploadProgressByFileKey,
    uploadCapByFileKey,
    uploading,
    canUpload,
    onFileSelect,
    onToggleCollectionName,
    onAddCollectionName,
    onAddAvailableCollectionName,
    onSetCollectionNamesForAllItems,
    onRemoveItem,
    onUpload,
}: FileUploadSectionProps) {
    const [settledCompletedFileKeys, setSettledCompletedFileKeys] = useState<
        Set<string>
    >(() => new Set());
    const settleTimeoutsRef = useRef<Map<string, number>>(new Map());
    const cardRefMap = useRef<Map<string, HTMLDivElement>>(new Map());
    const previousCardTopByKeyRef = useRef<Map<string, number>>(new Map());

    useEffect(
        () => () => {
            settleTimeoutsRef.current.forEach((timeoutID) => {
                window.clearTimeout(timeoutID);
            });
            settleTimeoutsRef.current.clear();
        },
        [],
    );

    const sameFileKeySet = (a: Set<string>, b: Set<string>) => {
        if (a.size !== b.size) {
            return false;
        }

        for (const value of a) {
            if (!b.has(value)) {
                return false;
            }
        }

        return true;
    };

    useEffect(() => {
        const activeFileKeys = new Set(
            selectedUploadItems.map(uploadQueueItemKey),
        );

        settleTimeoutsRef.current.forEach((timeoutID, fileKey) => {
            if (
                !activeFileKeys.has(fileKey) ||
                !completedFileKeys.has(fileKey)
            ) {
                window.clearTimeout(timeoutID);
                settleTimeoutsRef.current.delete(fileKey);
            }
        });

        setSettledCompletedFileKeys((current) => {
            const next = new Set<string>();
            current.forEach((fileKey) => {
                if (
                    activeFileKeys.has(fileKey) &&
                    completedFileKeys.has(fileKey)
                ) {
                    next.add(fileKey);
                }
            });
            return sameFileKeySet(current, next) ? current : next;
        });

        completedFileKeys.forEach((fileKey) => {
            if (
                !activeFileKeys.has(fileKey) ||
                settledCompletedFileKeys.has(fileKey) ||
                settleTimeoutsRef.current.has(fileKey)
            ) {
                return;
            }

            const timeoutID = window.setTimeout(() => {
                settleTimeoutsRef.current.delete(fileKey);
                setSettledCompletedFileKeys((current) => {
                    if (current.has(fileKey)) {
                        return current;
                    }

                    const next = new Set(current);
                    next.add(fileKey);
                    return next;
                });
            }, 1000);
            settleTimeoutsRef.current.set(fileKey, timeoutID);
        });
    }, [completedFileKeys, selectedUploadItems, settledCompletedFileKeys]);

    const orderedUploadItems = useMemo(() => {
        const pendingItems: LockerUploadCandidate[] = [];
        const completedItems: LockerUploadCandidate[] = [];

        for (const item of selectedUploadItems) {
            if (settledCompletedFileKeys.has(uploadQueueItemKey(item))) {
                completedItems.push(item);
            } else {
                pendingItems.push(item);
            }
        }

        return [...pendingItems, ...completedItems];
    }, [selectedUploadItems, settledCompletedFileKeys]);
    const shouldShowPerItemCollectionSelector = useMemo(() => {
        const uniqueParentPaths = new Set(
            selectedUploadItems.map(uploadItemParentPath),
        );
        return uniqueParentPaths.size > 1;
    }, [selectedUploadItems]);
    const sharedSelectedCollectionNames =
        selectedUploadItems.length > 0
            ? (selectedCollectionNamesByFileKey[
                  uploadQueueItemKey(selectedUploadItems[0]!)
              ] ?? [])
            : [];
    const sharedSuggestedCollectionNames = useMemo(
        () =>
            dedupeCollectionNames(
                selectedUploadItems.flatMap(
                    (item) => item.suggestedCollectionNames,
                ),
            ),
        [selectedUploadItems],
    );

    useLayoutEffect(() => {
        const nextCardTopByKey = new Map<string, number>();

        orderedUploadItems.forEach((item) => {
            const fileKey = uploadQueueItemKey(item);
            const element = cardRefMap.current.get(fileKey);
            if (!element) {
                return;
            }

            const nextTop = element.getBoundingClientRect().top;
            nextCardTopByKey.set(fileKey, nextTop);

            const previousTop = previousCardTopByKeyRef.current.get(fileKey);
            if (previousTop === undefined) {
                return;
            }

            const deltaY = previousTop - nextTop;
            if (Math.abs(deltaY) < 1) {
                return;
            }

            element.style.transition = "none";
            element.style.transform = `translateY(${deltaY}px)`;
            void element.getBoundingClientRect();
            element.style.transition =
                "transform 340ms cubic-bezier(0.22, 1, 0.36, 1)";
            element.style.transform = "translateY(0)";
        });

        previousCardTopByKeyRef.current = nextCardTopByKey;
    }, [orderedUploadItems]);

    return (
        <Stack sx={{ flex: 1, minHeight: 0 }}>
            <input
                ref={fileInputRef}
                type="file"
                multiple
                hidden
                onChange={onFileSelect}
            />

            <Stack
                sx={(theme) => ({
                    ...lockerScrollAreaSx(theme),
                    flex: 1,
                    minHeight: 0,
                    gap: "16px",
                    pb: "8px",
                })}
            >
                {selectedUploadItems.length === 0 ? (
                    <ButtonBase
                        onClick={() => fileInputRef.current?.click()}
                        sx={(theme) => ({
                            display: "flex",
                            flexDirection: "column",
                            alignItems: "center",
                            gap: "4px",
                            px: "20px",
                            py: "28px",
                            borderRadius: "20px",
                            border: `1px dashed ${theme.vars.palette.stroke.muted}`,
                            backgroundColor:
                                theme.vars.palette.background.paper,
                            textAlign: "center",
                            transition: "background-color 0.15s",
                            "&:hover": {
                                backgroundColor:
                                    theme.vars.palette.fill.faintHover,
                            },
                        })}
                    >
                        <Box
                            sx={{
                                width: 40,
                                height: 40,
                                borderRadius: "12px",
                                backgroundColor: "background.default",
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "center",
                                mb: "8px",
                                color: "accent.main",
                            }}
                        >
                            <HugeiconsIcon
                                icon={FileUploadIcon}
                                size={24}
                                strokeWidth={1.5}
                            />
                        </Box>
                        <Typography variant="small" sx={{ fontWeight: 600 }}>
                            {t("saveDocumentsTitle")}
                        </Typography>
                        <Typography variant="mini" sx={{ color: "text.muted" }}>
                            {t("dropToSaveToLocker")}
                        </Typography>
                    </ButtonBase>
                ) : (
                    <Stack sx={{ gap: "8px" }}>
                        {orderedUploadItems.map((item) => {
                            const fileKey = uploadQueueItemKey(item);
                            const isSettledCompleted =
                                settledCompletedFileKeys.has(fileKey);
                            return (
                                <Box
                                    key={fileKey}
                                    ref={(element: HTMLDivElement | null) => {
                                        if (element) {
                                            cardRefMap.current.set(
                                                fileKey,
                                                element,
                                            );
                                        } else {
                                            cardRefMap.current.delete(fileKey);
                                            previousCardTopByKeyRef.current.delete(
                                                fileKey,
                                            );
                                        }
                                    }}
                                    sx={{
                                        position: "relative",
                                        zIndex: isSettledCompleted ? 0 : 1,
                                        willChange: "transform",
                                    }}
                                >
                                    <UploadItemCard
                                        item={item}
                                        collections={collections}
                                        availableCollectionNames={
                                            availableCollectionNames
                                        }
                                        selectedCollectionNames={
                                            selectedCollectionNamesByFileKey[
                                                fileKey
                                            ] ?? []
                                        }
                                        suggestedCollectionNames={
                                            item.suggestedCollectionNames
                                        }
                                        showCollectionSelector={
                                            shouldShowPerItemCollectionSelector
                                        }
                                        isDone={completedFileKeys.has(fileKey)}
                                        isFailed={failedFileKeys.has(fileKey)}
                                        isUploading={uploadingFileKeys.has(
                                            fileKey,
                                        )}
                                        isQueued={
                                            !completedFileKeys.has(fileKey) &&
                                            !failedFileKeys.has(fileKey) &&
                                            !uploadingFileKeys.has(fileKey) &&
                                            uploading
                                        }
                                        uploadProgress={
                                            uploadProgressByFileKey[fileKey]
                                        }
                                        uploadCap={
                                            uploadCapByFileKey[fileKey] ?? 95
                                        }
                                        uploadInFlight={uploading}
                                        onToggleCollectionName={(
                                            name: string,
                                        ) =>
                                            onToggleCollectionName(
                                                fileKey,
                                                name,
                                            )
                                        }
                                        onAddCollectionName={(name: string) =>
                                            onAddCollectionName(fileKey, name)
                                        }
                                        canRemove={!uploading}
                                        onRemove={() => onRemoveItem(fileKey)}
                                    />
                                </Box>
                            );
                        })}
                    </Stack>
                )}
                {!uploading &&
                    !shouldShowPerItemCollectionSelector &&
                    selectedUploadItems.length > 0 && (
                        <Box sx={{ pt: "8px" }}>
                            <CollectionNameSelector
                                collections={collections}
                                availableNames={availableCollectionNames}
                                selectedNames={sharedSelectedCollectionNames}
                                suggestedNames={sharedSuggestedCollectionNames}
                                onToggleName={(name) =>
                                    onSetCollectionNamesForAllItems(
                                        toggleCollectionName(
                                            sharedSelectedCollectionNames,
                                            name,
                                        ),
                                    )
                                }
                                onAddCollectionName={(name) => {
                                    onAddAvailableCollectionName(name);
                                    onSetCollectionNamesForAllItems(
                                        addCollectionName(
                                            sharedSelectedCollectionNames,
                                            name,
                                        ),
                                    );
                                }}
                                disabled={uploading}
                            />
                        </Box>
                    )}
            </Stack>

            <Stack sx={{ pt: "16px", flexShrink: 0 }}>
                <LoadingButton
                    fullWidth
                    color="accent"
                    loading={uploading}
                    disabled={!canUpload}
                    sx={(theme) =>
                        lockerPrimaryButtonSx(theme, { loading: uploading })
                    }
                    onClick={() => void onUpload()}
                >
                    {t("saveRecord")}
                </LoadingButton>
            </Stack>
        </Stack>
    );
}

interface UploadItemCardProps {
    item: LockerUploadCandidate;
    collections: LockerCollection[];
    availableCollectionNames: string[];
    selectedCollectionNames: string[];
    suggestedCollectionNames: string[];
    showCollectionSelector: boolean;
    isDone: boolean;
    isFailed: boolean;
    isUploading: boolean;
    isQueued: boolean;
    uploadProgress: LockerUploadProgress | null | undefined;
    uploadCap: number;
    uploadInFlight: boolean;
    onToggleCollectionName: (name: string) => void;
    onAddCollectionName: (name: string) => void;
    canRemove: boolean;
    onRemove: () => void;
}

const UploadItemCard = React.memo(function UploadItemCard({
    item,
    collections,
    availableCollectionNames,
    selectedCollectionNames,
    suggestedCollectionNames,
    showCollectionSelector,
    isDone,
    isFailed,
    isUploading,
    isQueued,
    uploadProgress,
    uploadCap,
    uploadInFlight,
    onToggleCollectionName,
    onAddCollectionName,
    canRemove,
    onRemove,
}: UploadItemCardProps) {
    return (
        <Stack
            sx={(theme) => ({
                position: "relative",
                overflow: "hidden",
                borderRadius: "20px",
                backgroundColor: theme.vars.palette.background.paper,
            })}
        >
            <Stack
                direction="row"
                sx={{ alignItems: "center", gap: "12px", p: "12px" }}
            >
                <Box
                    sx={(theme) => ({
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        width: 40,
                        height: 40,
                        borderRadius: "12px",
                        backgroundColor: theme.vars.palette.background.default,
                        flexShrink: 0,
                    })}
                >
                    {lockerItemIcon("file", {
                        fileName: item.file.name,
                        size: 24,
                        strokeWidth: 1.5,
                    })}
                </Box>
                <Box sx={{ flex: 1, minWidth: 0 }}>
                    <Typography variant="small" noWrap>
                        {item.file.name}
                    </Typography>
                    <Typography variant="mini" sx={{ color: "text.muted" }}>
                        {formatFileSize(item.file.size)}
                    </Typography>
                </Box>
                <Box
                    sx={{
                        width: 28,
                        height: 28,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        flexShrink: 0,
                    }}
                >
                    {isUploading && (
                        <CircularProgress
                            size={18}
                            thickness={4}
                            sx={{ color: "text.muted" }}
                        />
                    )}
                    {isDone && (
                        <Box
                            sx={(theme) => ({
                                width: 18,
                                height: 18,
                                borderRadius: "50%",
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "center",
                                backgroundColor: theme.vars.palette.accent.main,
                                color: theme.vars.palette.accent.contrastText,
                            })}
                        >
                            <CheckRoundedIcon sx={{ fontSize: 12 }} />
                        </Box>
                    )}
                    {isFailed && (
                        <ErrorOutlineRoundedIcon
                            sx={{ color: "critical.main", fontSize: 20 }}
                        />
                    )}
                    {isQueued && (
                        <ScheduleRoundedIcon
                            sx={{ color: "text.muted", fontSize: 20 }}
                        />
                    )}
                    {canRemove && !isDone && !isFailed && (
                        <IconButton
                            aria-label={t("delete")}
                            onClick={onRemove}
                            size="small"
                            sx={(theme) => ({
                                width: 28,
                                height: 28,
                                p: 0,
                                borderRadius: "50%",
                                backgroundColor:
                                    theme.vars.palette.fill.faintHover,
                                color: theme.vars.palette.text.base,
                                "&:hover": {
                                    backgroundColor:
                                        theme.vars.palette.fill.faintHover,
                                },
                            })}
                        >
                            <HugeiconsIcon
                                icon={Cancel01Icon}
                                size={16}
                                strokeWidth={1.5}
                            />
                        </IconButton>
                    )}
                </Box>
            </Stack>
            {showCollectionSelector && (
                <Box sx={{ px: "12px", pb: "12px" }}>
                    <CollectionNameSelector
                        collections={collections}
                        availableNames={availableCollectionNames}
                        selectedNames={selectedCollectionNames}
                        suggestedNames={suggestedCollectionNames}
                        onToggleName={onToggleCollectionName}
                        onAddCollectionName={onAddCollectionName}
                        disabled={uploadInFlight}
                    />
                </Box>
            )}
            <LinearProgress
                variant="determinate"
                value={
                    isUploading
                        ? uploadProgressValue(uploadProgress, uploadCap)
                        : isDone
                          ? 100
                          : 0
                }
                sx={(theme) => ({
                    position: "absolute",
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 3,
                    borderRadius: 0,
                    opacity: isUploading || isDone ? 1 : 0,
                    backgroundColor: "rgba(16 113 255 / 0.12)",
                    "& .MuiLinearProgress-bar": {
                        backgroundColor: theme.vars.palette.accent.main,
                        transition:
                            uploadProgress?.phase === "finalizing"
                                ? theme.transitions.create("transform", {
                                      duration: 2200,
                                      easing: "ease-out",
                                  })
                                : undefined,
                    },
                })}
            />
        </Stack>
    );
}, areUploadItemCardPropsEqual);

function areUploadItemCardPropsEqual(
    previous: UploadItemCardProps,
    next: UploadItemCardProps,
) {
    return (
        previous.item === next.item &&
        previous.collections === next.collections &&
        previous.availableCollectionNames === next.availableCollectionNames &&
        previous.selectedCollectionNames === next.selectedCollectionNames &&
        previous.suggestedCollectionNames === next.suggestedCollectionNames &&
        previous.showCollectionSelector === next.showCollectionSelector &&
        previous.isDone === next.isDone &&
        previous.isFailed === next.isFailed &&
        previous.isUploading === next.isUploading &&
        previous.isQueued === next.isQueued &&
        previous.uploadProgress === next.uploadProgress &&
        previous.uploadCap === next.uploadCap &&
        previous.uploadInFlight === next.uploadInFlight &&
        previous.canRemove === next.canRemove
    );
}

const CollectionNameSelector: React.FC<{
    collections: LockerCollection[];
    availableNames: string[];
    selectedNames: string[];
    suggestedNames: string[];
    onToggleName: (name: string) => void;
    onAddCollectionName: (name: string) => void;
    disabled?: boolean;
}> = ({
    collections,
    availableNames,
    selectedNames,
    suggestedNames,
    onToggleName,
    onAddCollectionName,
    disabled,
}) => {
    const [createOpen, setCreateOpen] = useState(false);
    const [createName, setCreateName] = useState("");
    const selectedNameMap = useMemo(
        () =>
            new Map(
                selectedNames.map((name) => [
                    normalizeCollectionName(name),
                    name,
                ]),
            ),
        [selectedNames],
    );
    const displayNames = useMemo(() => {
        const allNames = dedupeCollectionNames([
            ...collections.map((collection) => collection.name),
            ...availableNames,
            ...selectedNames,
        ]);
        const suggestedNameSet = new Set(
            suggestedNames.map((name) => normalizeCollectionName(name)),
        );
        const sortedSuggestedNames = allNames
            .filter((name) => {
                const normalizedName = normalizeCollectionName(name);
                return suggestedNameSet.has(normalizedName);
            })
            .sort((a, b) =>
                a.localeCompare(b, undefined, { sensitivity: "base" }),
            );
        const sortedRemainingNames = allNames
            .filter((name) => {
                const normalizedName = normalizeCollectionName(name);
                return !suggestedNameSet.has(normalizedName);
            })
            .sort((a, b) =>
                a.localeCompare(b, undefined, { sensitivity: "base" }),
            );
        return [...sortedSuggestedNames, ...sortedRemainingNames];
    }, [availableNames, collections, selectedNames, suggestedNames]);

    const handleAddCollectionName = useCallback(() => {
        const trimmedName = createName.trim();
        if (!trimmedName) {
            return;
        }

        onAddCollectionName(trimmedName);
        setCreateName("");
        setCreateOpen(false);
    }, [createName, onAddCollectionName]);

    return (
        <Box>
            <CollectionChipRow
                items={displayNames.map((name) => ({
                    key: name,
                    label: name,
                    selected: selectedNameMap.has(
                        normalizeCollectionName(name),
                    ),
                    onClick: () => onToggleName(name),
                }))}
                createOpen={createOpen}
                disabled={disabled}
                onCreateClick={() => setCreateOpen((open) => !open)}
            />
            {createOpen && (
                <CreateCollectionRow
                    value={createName}
                    onChange={setCreateName}
                    onSubmit={handleAddCollectionName}
                    onCancel={() => setCreateOpen(false)}
                    disabled={disabled}
                />
            )}
        </Box>
    );
};
