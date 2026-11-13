import { lockerSheetContainerSx, lockerSheetPaperSx } from "@/styles/dialog";
import {
    lockerColorSx,
    lockerTextBodyBoldSx,
    lockerTextBodySx,
    lockerTextH2Sx,
    lockerTextMiniSx,
} from "@/styles/tokens";
import type { LockerCollection, LockerItem } from "@/types";
import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import CheckRoundedIcon from "@mui/icons-material/CheckRounded";
import {
    Box,
    Chip,
    Dialog,
    IconButton,
    Stack,
    Typography,
} from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import log from "ente-base/log";
import { t } from "i18next";
import { useCallback, useEffect, useId, useState } from "react";

interface RestoreItemDialogProps {
    restoreItem: LockerItem | null;
    restoreCollections: LockerCollection[];
    onClose: () => void;
    onRestoreItem?: (
        item: LockerItem,
        collectionID: number,
    ) => void | Promise<void>;
}
export function RestoreItemDialog({
    restoreItem,
    restoreCollections,
    onClose,
    onRestoreItem,
}: RestoreItemDialogProps) {
    const restoreTitleID = useId();
    const restoreDialogOpen = restoreItem !== null;
    const [restoreCollectionID, setRestoreCollectionID] = useState<
        number | null
    >(null);
    const [restoreError, setRestoreError] = useState<string | null>(null);
    const [restoringItem, setRestoringItem] = useState(false);
    const restoreItemID = restoreItem?.id ?? null;
    const [previousItemID, setPreviousItemID] = useState(restoreItemID);
    if (previousItemID !== restoreItemID) {
        setPreviousItemID(restoreItemID);
        setRestoreCollectionID(null);
    }

    useEffect(() => {
        if (
            restoreCollectionID !== null &&
            !restoreCollections.some(
                (collection) => collection.id === restoreCollectionID,
            )
        ) {
            setRestoreCollectionID(null);
        }
    }, [restoreCollectionID, restoreCollections]);

    useEffect(() => {
        if (restoreItem === null) {
            setRestoreError(null);
            setRestoringItem(false);
        }
    }, [restoreItem]);

    const handleRestoreConfirm = useCallback(async () => {
        if (
            !restoreItem ||
            restoreCollectionID === null ||
            !onRestoreItem ||
            restoringItem
        ) {
            return;
        }

        setRestoringItem(true);
        setRestoreError(null);
        try {
            await Promise.resolve(
                onRestoreItem(restoreItem, restoreCollectionID),
            );
            onClose();
            setRestoreCollectionID(null);
        } catch (error) {
            log.error("Failed to restore Locker item", error);
            setRestoreError(
                error instanceof Error ? error.message : t("generic_error"),
            );
        } finally {
            setRestoringItem(false);
        }
    }, [
        onRestoreItem,
        restoreCollectionID,
        restoreItem,
        restoringItem,
        onClose,
    ]);

    const onCloseRestoreDialog = () => {
        if (restoringItem) return;
        onClose();
        setRestoreCollectionID(null);
        setRestoreError(null);
    };
    const handleSelectCollection = (id: number) => {
        setRestoreCollectionID(id);
        setRestoreError(null);
    };
    return (
        <Dialog
            slotProps={{
                paper: { sx: lockerSheetPaperSx },
                container: { sx: lockerSheetContainerSx },
            }}
            open={restoreDialogOpen}
            aria-labelledby={restoreTitleID}
            onClose={() => {
                if (!restoringItem) {
                    onCloseRestoreDialog();
                }
            }}
            fullWidth
            maxWidth="xs"
        >
            <Stack>
                <Stack
                    direction="row"
                    sx={{ alignItems: "center", gap: 1.5, minHeight: 38 }}
                >
                    <Typography
                        id={restoreTitleID}
                        noWrap
                        sx={{ ...lockerTextH2Sx, flex: 1, minWidth: 0 }}
                    >
                        {t("restoreToCollection")}
                    </Typography>
                    <IconButton
                        aria-label={t("cancel")}
                        disabled={restoringItem}
                        onClick={() => {
                            if (!restoringItem) {
                                onCloseRestoreDialog();
                            }
                        }}
                        sx={(theme) => ({
                            width: 36,
                            height: 36,
                            borderRadius: "50%",
                            p: 0,
                            flexShrink: 0,
                            ...lockerColorSx(theme, {
                                backgroundColor: "fillLight",
                                color: "iconColor",
                            }),
                            "&:hover": {
                                ...lockerColorSx(theme, {
                                    backgroundColor: "fillHover",
                                }),
                            },
                        })}
                    >
                        <HugeiconsIcon
                            icon={Cancel01Icon}
                            size={18}
                            strokeWidth={1.5}
                        />
                    </IconButton>
                </Stack>
                <Typography
                    sx={(theme) => ({
                        ...lockerTextMiniSx,
                        mt: 2.5,
                        mb: 1,
                        ...lockerColorSx(theme, { color: "textLight" }),
                    })}
                >
                    {t("collections")}
                </Typography>
                <Box sx={{ display: "flex", flexWrap: "wrap", gap: 1 }}>
                    {restoreCollections.length > 0 ? (
                        restoreCollections.map((collection) => (
                            <Chip
                                key={collection.id}
                                label={collection.name}
                                icon={
                                    restoreCollectionID === collection.id ? (
                                        <CheckRoundedIcon
                                            sx={{ fontSize: 14 }}
                                        />
                                    ) : undefined
                                }
                                disabled={restoringItem}
                                onClick={() =>
                                    handleSelectCollection(collection.id)
                                }
                                sx={(theme) => ({
                                    height: 36,
                                    borderRadius: "9999px",
                                    px: "14px",
                                    border: "1px solid",
                                    ...lockerColorSx(theme, {
                                        backgroundColor:
                                            restoreCollectionID ===
                                            collection.id
                                                ? "primaryLight"
                                                : "fillLight",
                                        color:
                                            restoreCollectionID ===
                                            collection.id
                                                ? "primary"
                                                : "textBase",
                                        ...(restoreCollectionID ===
                                        collection.id
                                            ? {
                                                  borderColor:
                                                      "primaryStroke" as const,
                                              }
                                            : {}),
                                    }),
                                    ...(restoreCollectionID === collection.id
                                        ? {}
                                        : { borderColor: "transparent" }),
                                    "& .MuiChip-label": {
                                        ...lockerTextBodySx,
                                        px: 0,
                                    },
                                    "& .MuiChip-icon": {
                                        ml: 0,
                                        mr: 0.75,
                                        ...lockerColorSx(theme, {
                                            color: "primary",
                                        }),
                                    },
                                })}
                            />
                        ))
                    ) : (
                        <Typography
                            sx={(theme) => ({
                                ...lockerTextBodySx,
                                ...lockerColorSx(theme, { color: "textLight" }),
                            })}
                        >
                            {t("noCollectionsAvailableForSelection")}
                        </Typography>
                    )}
                </Box>
                {restoreError && (
                    <Typography
                        sx={(theme) => ({
                            ...lockerTextMiniSx,
                            mt: 1.5,
                            ...lockerColorSx(theme, { color: "warning" }),
                        })}
                    >
                        {restoreError}
                    </Typography>
                )}
                <LoadingButton
                    fullWidth
                    variant="contained"
                    loading={restoringItem}
                    disabled={restoreCollectionID === null}
                    onClick={handleRestoreConfirm}
                    sx={(theme) => ({
                        ...lockerTextBodyBoldSx,
                        mt: 3,
                        minHeight: 52,
                        borderRadius: "20px",
                        textTransform: "none",
                        ...lockerColorSx(theme, {
                            backgroundColor: "primary",
                            color: "specialWhite",
                        }),
                        "&:hover": {
                            ...lockerColorSx(theme, {
                                backgroundColor: "primaryDark",
                            }),
                        },
                        "&.Mui-disabled": {
                            ...lockerColorSx(theme, {
                                backgroundColor: "fillDarkest",
                                color: "textLighter",
                            }),
                        },
                    })}
                >
                    {t("restore")}
                </LoadingButton>
            </Stack>
        </Dialog>
    );
}
