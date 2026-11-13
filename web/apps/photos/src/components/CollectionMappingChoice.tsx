import FolderIcon from "@mui/icons-material/Folder";
import FolderCopyIcon from "@mui/icons-material/FolderCopy";
import {
    Dialog,
    DialogContent,
    DialogTitle,
    Stack,
    Typography,
} from "@mui/material";
import { SpacedRow } from "ente-base/components/containers";
import { DialogCloseIconButton } from "ente-base/components/mui/DialogCloseIconButton";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import type { CollectionMapping } from "ente-base/types/ipc";
import { t } from "i18next";
import React from "react";

type CollectionMappingChoiceProps = ModalVisibilityProps & {
    onSelect: (mapping: CollectionMapping) => void;
};

export const CollectionMappingChoice: React.FC<
    CollectionMappingChoiceProps
> = ({ open, onClose, onSelect }) => (
    <Dialog
        open={open}
        onClose={onClose}
        fullWidth
        slotProps={{ paper: { sx: { maxWidth: "360px", padding: "12px" } } }}
    >
        <SpacedRow sx={{ pr: "4px" }}>
            <DialogTitle>{t("multi_folder_upload")}</DialogTitle>
            <DialogCloseIconButton {...{ onClose }} />
        </SpacedRow>

        <DialogContent
            sx={{
                display: "flex",
                flexDirection: "column",
                "&&": { paddingBlockStart: "12px" },
                gap: "20px",
            }}
        >
            <Typography sx={{ color: "text.muted" }}>
                {t("upload_to_choice")}
            </Typography>
            <Stack sx={{ gap: "12px" }}>
                <FocusVisibleButton
                    color="accent"
                    startIcon={<FolderIcon />}
                    onClick={() => {
                        onClose();
                        onSelect("root");
                    }}
                >
                    {t("upload_to_single_album")}
                </FocusVisibleButton>

                <FocusVisibleButton
                    color="accent"
                    startIcon={<FolderCopyIcon />}
                    onClick={() => {
                        onClose();
                        onSelect("parent");
                    }}
                >
                    {t("upload_to_album_per_folder")}
                </FocusVisibleButton>
            </Stack>
        </DialogContent>
    </Dialog>
);
