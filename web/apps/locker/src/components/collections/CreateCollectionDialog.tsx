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
import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Dialog, IconButton, Stack, Typography } from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { t } from "i18next";
import { useCallback, useState } from "react";

interface CreateCollectionDialogProps {
    open: boolean;
    onClose: () => void;
    onCreateCollection?: (name: string) => Promise<number>;
    onSelectCollection: (id: number) => void;
}
export function CreateCollectionDialog({
    open: createCollectionOpen,
    onClose: onCloseCreateCollectionDialog,
    onCreateCollection,
    onSelectCollection,
}: CreateCollectionDialogProps) {
    const onClose = onCloseCreateCollectionDialog;
    const [createCollectionName, setCreateCollectionName] = useState("");
    const [creatingCollection, setCreatingCollection] = useState(false);
    const [createCollectionError, setCreateCollectionError] = useState<
        string | null
    >(null);
    const [wasOpen, setWasOpen] = useState(createCollectionOpen);
    if (wasOpen !== createCollectionOpen) {
        setWasOpen(createCollectionOpen);
        if (createCollectionOpen) {
            setCreateCollectionName("");
            setCreateCollectionError(null);
        }
    }
    const handleCreateCollectionConfirm = useCallback(async () => {
        if (!onCreateCollection || !createCollectionName.trim()) {
            return;
        }

        setCreatingCollection(true);
        setCreateCollectionError(null);
        try {
            const newCollectionID = await onCreateCollection(
                createCollectionName.trim(),
            );
            onClose();
            setCreateCollectionName("");
            onSelectCollection(newCollectionID);
        } catch (error) {
            setCreateCollectionError(
                error instanceof Error
                    ? error.message
                    : t("failedToCreateCollection"),
            );
        } finally {
            setCreatingCollection(false);
        }
    }, [createCollectionName, onCreateCollection, onSelectCollection, onClose]);

    const handleNameChange = (value: string) => {
        setCreateCollectionName(value);
        setCreateCollectionError(null);
    };
    return (
        <Dialog
            slotProps={{
                paper: { sx: lockerSheetPaperSx },
                container: { sx: lockerSheetContainerSx },
            }}
            open={createCollectionOpen}
            onClose={() => {
                if (!creatingCollection) {
                    onCloseCreateCollectionDialog();
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
                        {t("createCollection")}
                    </Typography>
                    <IconButton
                        aria-label={t("close")}
                        onClick={onCloseCreateCollectionDialog}
                        disabled={creatingCollection}
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
                        value={createCollectionName}
                        onChange={(event) =>
                            handleNameChange(event.target.value)
                        }
                        label={t("enterCollectionName")}
                        required
                        autoFocus
                        disabled={creatingCollection}
                        onKeyDown={(event) => {
                            if (event.key === "Enter") {
                                void handleCreateCollectionConfirm();
                            }
                        }}
                    />
                </Box>
                {createCollectionError && (
                    <Typography
                        sx={(theme) => ({
                            ...lockerTextMiniSx,
                            mt: 1.5,
                            ...lockerColorSx(theme, { color: "warning" }),
                        })}
                    >
                        {createCollectionError}
                    </Typography>
                )}
                <LoadingButton
                    fullWidth
                    color="primary"
                    loading={creatingCollection}
                    disabled={!createCollectionName.trim()}
                    onClick={handleCreateCollectionConfirm}
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
                            loading: creatingCollection,
                        }),
                    })}
                >
                    {t("createCollectionButton")}
                </LoadingButton>
            </Stack>
        </Dialog>
    );
}
