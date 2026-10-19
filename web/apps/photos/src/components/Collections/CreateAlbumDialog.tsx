import { collectionDialogBodyMutedSx as bodyMutedSx } from "@/components/CollectionDialog/styles";
import type { RemotePullOpts } from "@/components/gallery";
import ArrowForwardIcon from "@mui/icons-material/ArrowForward";
import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    DialogTitle,
    Paper,
    Snackbar,
    Stack,
    Typography,
} from "@mui/material";
import { FilledIconButton } from "ente-base/components/mui";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import {
    createAlbum,
    createHiddenAlbum,
} from "ente-new/photos/services/collection";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import React, { useState } from "react";

interface CreateAlbumDialogProps extends ModalVisibilityProps {
    isHidden: boolean;
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
    onSelectCollectionID: (id: number) => void;
}

// Shared album creation flow, including refresh and success notification.
export const CreateAlbumDialog: React.FC<CreateAlbumDialogProps> = ({
    open,
    onClose,
    isHidden,
    onRemotePull,
    onSelectCollectionID,
}) => {
    const { showNotification } = usePhotosAppContext();
    const [albumCreatedToast, setAlbumCreatedToast] = useState<{
        open: boolean;
        albumId?: number;
        albumName?: string;
    }>({ open: false });

    const handleCreateAlbum = (albumName: string) => {
        void (async () => {
            try {
                const newAlbum = isHidden
                    ? await createHiddenAlbum(albumName)
                    : await createAlbum(albumName);
                await onRemotePull();

                setAlbumCreatedToast({
                    open: true,
                    albumId: newAlbum.id,
                    albumName: albumName,
                });
            } catch {
                showNotification({
                    color: "critical",
                    title: t("generic_error_retry"),
                });
            }
        })();
    };

    return (
        <>
            <SingleInputDialog
                {...{ open, onClose }}
                variant="v2"
                title={t("new_album")}
                label={t("album_name")}
                submitButtonTitle={t("create")}
                onSubmit={handleCreateAlbum}
            />
            <Snackbar
                open={albumCreatedToast.open}
                anchorOrigin={{ horizontal: "right", vertical: "bottom" }}
            >
                <Paper sx={{ width: "min(360px, 100svw)" }}>
                    <DialogTitle>
                        <Stack
                            direction="row"
                            sx={{
                                justifyContent: "space-between",
                                alignItems: "center",
                            }}
                        >
                            <Box>
                                <Typography variant="h3">
                                    {t("album_created")}
                                </Typography>
                                <Typography
                                    sx={[bodyMutedSx, { marginTop: "4px" }]}
                                >
                                    {albumCreatedToast.albumName &&
                                    albumCreatedToast.albumName.length > 16
                                        ? albumCreatedToast.albumName.substring(
                                              0,
                                              16,
                                          ) + "..."
                                        : albumCreatedToast.albumName}
                                </Typography>
                            </Box>
                            <Stack direction="row" sx={{ gap: 1 }}>
                                <FilledIconButton
                                    onClick={() => {
                                        if (albumCreatedToast.albumId) {
                                            onSelectCollectionID(
                                                albumCreatedToast.albumId,
                                            );
                                        }
                                        setAlbumCreatedToast((prev) => ({
                                            ...prev,
                                            open: false,
                                        }));
                                    }}
                                >
                                    <ArrowForwardIcon />
                                </FilledIconButton>
                                <FilledIconButton
                                    onClick={() =>
                                        setAlbumCreatedToast((prev) => ({
                                            ...prev,
                                            open: false,
                                        }))
                                    }
                                >
                                    <CloseIcon />
                                </FilledIconButton>
                            </Stack>
                        </Stack>
                    </DialogTitle>
                </Paper>
            </Snackbar>
        </>
    );
};
