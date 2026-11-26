import CloseIcon from "@mui/icons-material/Close";
import { Dialog, DialogTitle, IconButton, Stack } from "@mui/material";
import {
    v2CloseButtonSx,
    v2HeaderRowSx,
    v2PaperSx,
} from "ente-base/components/SingleInput.styles";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { t } from "i18next";
import React, { useId } from "react";

type PhotosFormDialogProps = React.PropsWithChildren<
    ModalVisibilityProps & { title: string; descriptionID?: string }
>;

export const PhotosFormDialog: React.FC<PhotosFormDialogProps> = ({
    open,
    onClose,
    title,
    descriptionID,
    children,
}) => {
    const titleID = useId();

    return (
        <Dialog
            open={open}
            onClose={onClose}
            maxWidth={false}
            aria-labelledby={titleID}
            aria-describedby={descriptionID}
            slotProps={{ paper: { sx: v2PaperSx } }}
        >
            <Stack sx={{ p: "20px", gap: "20px" }}>
                <Stack direction="row" sx={v2HeaderRowSx}>
                    <DialogTitle
                        id={titleID}
                        sx={{
                            "&&": { p: 0 },
                            fontSize: "20px",
                            lineHeight: "28px",
                            fontWeight: 600,
                        }}
                    >
                        {title}
                    </DialogTitle>
                    <IconButton
                        aria-label={t("close")}
                        onClick={onClose}
                        sx={v2CloseButtonSx}
                    >
                        <CloseIcon sx={{ fontSize: 18 }} />
                    </IconButton>
                </Stack>
                {children}
            </Stack>
        </Dialog>
    );
};
