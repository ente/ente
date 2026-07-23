import { CollectionChipRow } from "@/components/createItemDialog/CollectionChipRow";
import {
    lockerItemIcon,
    lockerItemIconConfig,
} from "@/components/lockerItemIcons";
import type { LockerUploadProgress } from "@/services/remote";
import type { LockerCollection, LockerUploadCandidate } from "@/types";
import CheckRoundedIcon from "@mui/icons-material/CheckRounded";
import CloudUploadOutlinedIcon from "@mui/icons-material/CloudUploadOutlined";
import DeleteOutlineRoundedIcon from "@mui/icons-material/DeleteOutlineRounded";
import ErrorOutlineRoundedIcon from "@mui/icons-material/ErrorOutlineRounded";
import ScheduleRoundedIcon from "@mui/icons-material/ScheduleRounded";
import {
    Box,
    ButtonBase,
    IconButton,
    LinearProgress,
    Stack,
    TextField,
    Typography,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
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
} from "./fileUploadHelpers";

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
    onClose: () => void;
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
    onClose,
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
        <Stack sx={{ flex: 1, minHeight: 0, pt: 0.5 }}>
            <input
                ref={fileInputRef}
                type="file"
                multiple
                hidden
                onChange={onFileSelect}
            />

            <Stack
                sx={{
                    flex: 1,
                    minHeight: 0,
                    overflowY: "auto",
                    gap: 2.5,
                    pr: 0.5,
                    pb: 2,
                }}
            >
                {selectedUploadItems.length === 0 ? (
                    <ButtonBase
                        onClick={() => fileInputRef.current?.click()}
                        sx={(theme) => ({
                            display: "flex",
                            flexDirection: "column",
                            alignItems: "center",
                            gap: 1.5,
                            p: 4,
                            borderRadius: "16px",
                            border: `2px dashed ${theme.vars.palette.divider}`,
                            backgroundColor: theme.vars.palette.fill.faint,
                            transition: "background-color 0.15s",
                            "&:hover": {
                                backgroundColor:
                                    theme.vars.palette.fill.faintHover,
                            },
                        })}
                    >
                        <CloudUploadOutlinedIcon
                            sx={{ fontSize: 40, color: "text.faint" }}
                        />
                        <Typography variant="body" sx={{ fontWeight: 600 }}>
                            {t("saveDocumentsTitle")}
                        </Typography>
                        <Typography
                            variant="small"
                            sx={{ color: "text.muted" }}
                        >
                            {t("dropToSaveToLocker")}
                        </Typography>
                    </ButtonBase>
                ) : (
                    <Stack sx={{ gap: 1.25 }}>
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
            </Stack>

            <Stack
                sx={(theme) => ({
                    gap: 1.5,
                    pt: 2,
                    borderTop: `1px solid ${theme.vars.palette.stroke.faint}`,
                    backgroundColor: theme.vars.palette.background.paper,
                })}
            >
                {!uploading &&
                    !shouldShowPerItemCollectionSelector &&
                    selectedUploadItems.length > 0 && (
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
                    )}

                <Stack direction="row" sx={{ gap: 1 }}>
                    <FocusVisibleButton
                        fullWidth
                        color="secondary"
                        onClick={onClose}
                        disabled={uploading}
                        sx={{ borderRadius: "16px", py: 1.25 }}
                    >
                        {t("cancel")}
                    </FocusVisibleButton>
                    <LoadingButton
                        fullWidth
                        color="accent"
                        loading={uploading}
                        disabled={!canUpload}
                        sx={{ borderRadius: "16px", py: 1.25 }}
                        onClick={() => void onUpload()}
                    >
                        {t("saveRecord")}
                    </LoadingButton>
                </Stack>
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
            sx={{
                borderRadius: "12px",
                backgroundColor: (theme) => theme.vars.palette.fill.faint,
                overflow: "hidden",
                display: "flex",
                flexDirection: "column",
            }}
        >
            <Stack
                direction="row"
                sx={{
                    alignItems: "center",
                    gap: 1.5,
                    p: 2,
                    position: "relative",
                }}
            >
                <Box
                    sx={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        width: 48,
                        height: 48,
                        borderRadius: "12px",
                        backgroundColor: lockerItemIconConfig(
                            "file",
                            item.file.name,
                        ).backgroundColor,
                        flexShrink: 0,
                    }}
                >
                    {lockerItemIcon("file", {
                        fileName: item.file.name,
                        size: 24,
                        strokeWidth: 1.9,
                    })}
                </Box>
                <Box sx={{ flex: 1, minWidth: 0, pr: canRemove ? 5 : 0 }}>
                    <Typography variant="body" noWrap>
                        {item.file.name}
                    </Typography>
                    <Typography variant="small" sx={{ color: "text.faint" }}>
                        {formatFileSize(item.file.size)}
                    </Typography>
                </Box>
                {isDone && (
                    <Box
                        sx={() => ({
                            width: 24,
                            height: 24,
                            borderRadius: "50%",
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            backgroundColor: "#1071FF",
                            color: "#FFFFFF",
                            flexShrink: 0,
                        })}
                    >
                        <CheckRoundedIcon sx={{ fontSize: 16 }} />
                    </Box>
                )}
                {isFailed && (
                    <ErrorOutlineRoundedIcon
                        sx={{
                            color: "critical.main",
                            fontSize: 20,
                            flexShrink: 0,
                        }}
                    />
                )}
                {isQueued && (
                    <ScheduleRoundedIcon
                        sx={{
                            color: "text.muted",
                            fontSize: 20,
                            flexShrink: 0,
                        }}
                    />
                )}
                {canRemove && !isDone && !isFailed && (
                    <IconButton
                        aria-label={t("delete")}
                        onClick={onRemove}
                        size="small"
                        sx={(theme) => ({
                            position: "absolute",
                            top: 12,
                            right: 12,
                            width: 30,
                            height: 30,
                            borderRadius: "10px",
                            backgroundColor: "transparent",
                            color: theme.vars.palette.text.muted,
                            flexShrink: 0,
                            "&:hover": {
                                backgroundColor:
                                    theme.vars.palette.fill.faintHover,
                                color: theme.vars.palette.text.base,
                            },
                        })}
                    >
                        <DeleteOutlineRoundedIcon sx={{ fontSize: 16 }} />
                    </IconButton>
                )}
            </Stack>
            {showCollectionSelector && (
                <Box sx={{ px: 2, pt: 1.5, pb: 2, flexShrink: 0 }}>
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
            <Box sx={{ mt: "auto", height: 4, flexShrink: 0 }}>
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
                        height: 4,
                        borderRadius: 0,
                        opacity: isUploading || isDone ? 1 : 0,
                        "& .MuiLinearProgress-bar": {
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
            </Box>
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
                <Stack sx={{ gap: 1, mt: 1.25 }}>
                    <Stack
                        direction="row"
                        sx={{ gap: 1, alignItems: "center" }}
                    >
                        <TextField
                            size="small"
                            fullWidth
                            autoFocus
                            placeholder={t("enterCollectionName")}
                            sx={{
                                "& .MuiInputBase-root": {
                                    height: 44,
                                    borderRadius: "14px",
                                },
                                "& .MuiInputBase-input": { pt: 1, pb: 0.5 },
                            }}
                            value={createName}
                            onChange={(event) =>
                                setCreateName(event.target.value)
                            }
                            onKeyDown={(event) => {
                                if (event.key === "Escape") {
                                    event.preventDefault();
                                    event.stopPropagation();
                                    setCreateOpen(false);
                                    return;
                                }
                                if (event.key === "Enter") {
                                    event.preventDefault();
                                    handleAddCollectionName();
                                }
                            }}
                            disabled={disabled}
                        />
                        <LoadingButton
                            color="accent"
                            disabled={!createName.trim() || disabled}
                            aria-label={t("create")}
                            onClick={handleAddCollectionName}
                            sx={{
                                minWidth: 0,
                                width: 44,
                                height: 44,
                                p: 0,
                                borderRadius: "14px",
                                flexShrink: 0,
                            }}
                        >
                            <CheckRoundedIcon />
                        </LoadingButton>
                    </Stack>
                </Stack>
            )}
        </Box>
    );
};
