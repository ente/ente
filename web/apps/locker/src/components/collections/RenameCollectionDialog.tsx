import { FormField } from "@/components/ui/FormField";
import { lockerSheetContainerSx, lockerSheetPaperSx } from "@/styles/dialog";
import {
    lockerHeaderIconButtonSx,
    lockerPrimaryButtonSx,
} from "@/styles/fields";
import {
    lockerColorSx,
    lockerTextBodyBoldSx,
    lockerTextH2Sx,
    lockerTextMiniSx,
} from "@/styles/tokens";
import type { LockerCollection } from "@/types";
import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Dialog, IconButton, Stack, Typography } from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import log from "ente-base/log";
import { t } from "i18next";
import { useCallback, useEffect, useState } from "react";

interface RenameCollectionDialogProps {
    collection: LockerCollection | null;
    onClose: () => void;
    onRenameCollection?: (
        collectionID: number,
        newName: string,
    ) => void | Promise<void>;
}
export function RenameCollectionDialog({
    collection,
    onClose,
    onRenameCollection,
}: RenameCollectionDialogProps) {
    const renameCollectionID = collection?.id ?? null;
    const renameCollectionOpen = collection !== null;
    const [renameValue, setRenameValue] = useState(collection?.name ?? "");
    const [renameError, setRenameError] = useState<string | null>(null);
    const [renamingCollection, setRenamingCollection] = useState(false);
    const [previousCollection, setPreviousCollection] = useState(collection);
    if (previousCollection !== collection) {
        setPreviousCollection(collection);
        if (collection) {
            setRenameValue(collection.name);
            setRenameError(null);
        }
    }
    useEffect(() => {
        if (renameCollectionID === null) {
            setRenameError(null);
            setRenamingCollection(false);
        }
    }, [renameCollectionID]);

    const handleRenameConfirm = useCallback(async () => {
        if (
            renameCollectionID === null ||
            !renameValue.trim() ||
            !onRenameCollection ||
            renamingCollection
        ) {
            return;
        }

        setRenamingCollection(true);
        setRenameError(null);
        try {
            await Promise.resolve(
                onRenameCollection(renameCollectionID, renameValue.trim()),
            );
            onClose();
            setRenameValue("");
        } catch (error) {
            log.error("Failed to rename Locker collection", error);
            setRenameError(
                error instanceof Error ? error.message : t("generic_error"),
            );
        } finally {
            setRenamingCollection(false);
        }
    }, [
        onClose,
        onRenameCollection,
        renameCollectionID,
        renameValue,
        renamingCollection,
    ]);

    const onCloseRenameDialog = () => {
        if (renamingCollection) return;
        onClose();
        setRenameError(null);
    };
    const handleNameChange = (value: string) => {
        setRenameValue(value);
        setRenameError(null);
    };
    return (
        <Dialog
            slotProps={{
                paper: { sx: lockerSheetPaperSx },
                container: { sx: lockerSheetContainerSx },
            }}
            open={renameCollectionOpen}
            onClose={() => {
                if (!renamingCollection) {
                    onCloseRenameDialog();
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
                        sx={{ ...lockerTextH2Sx, flex: 1, minWidth: 0 }}
                    >
                        {t("renameCollection")}
                    </Typography>
                    <IconButton
                        aria-label={t("close")}
                        onClick={onCloseRenameDialog}
                        disabled={renamingCollection}
                        sx={lockerHeaderIconButtonSx}
                    >
                        <HugeiconsIcon
                            icon={Cancel01Icon}
                            size={18}
                            strokeWidth={1.5}
                        />
                    </IconButton>
                </Stack>
                <Box sx={{ mt: 2.5 }}>
                    <FormField
                        value={renameValue}
                        onChange={(event) =>
                            handleNameChange(event.target.value)
                        }
                        label={t("enterCollectionName")}
                        required
                        autoFocus
                        disabled={renamingCollection}
                        onKeyDown={(event) => {
                            if (event.key === "Enter") {
                                void handleRenameConfirm();
                            }
                        }}
                    />
                </Box>
                {renameError && (
                    <Typography
                        sx={(theme) => ({
                            ...lockerTextMiniSx,
                            mt: 1.5,
                            ...lockerColorSx(theme, { color: "warning" }),
                        })}
                    >
                        {renameError}
                    </Typography>
                )}
                <LoadingButton
                    fullWidth
                    color="primary"
                    loading={renamingCollection}
                    disabled={!renameValue.trim()}
                    onClick={handleRenameConfirm}
                    sx={(theme) => ({
                        ...lockerTextBodyBoldSx,
                        mt: 3,
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
                        ...lockerPrimaryButtonSx(theme, {
                            loading: renamingCollection,
                        }),
                    })}
                >
                    {t("save")}
                </LoadingButton>
            </Stack>
        </Dialog>
    );
}
