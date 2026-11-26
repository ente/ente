import { Folder01Icon, FolderLibraryIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { ButtonBase, Stack, Typography } from "@mui/material";
import {
    peopleActionFocusSx,
    v2SubmitButtonSx,
} from "ente-base/components/SingleInput.styles";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import type { CollectionMapping } from "ente-base/types/ipc";
import { t } from "i18next";
import React, { useId } from "react";
import { PhotosFormDialog } from "./PhotosFormDialog";

type CollectionMappingChoiceProps = ModalVisibilityProps & {
    onSelect: (mapping: CollectionMapping) => void;
};

export const CollectionMappingChoice: React.FC<
    CollectionMappingChoiceProps
> = ({ open, onClose, onSelect }) => {
    const descriptionID = useId();

    const handleSelect = (mapping: CollectionMapping) => {
        onClose();
        onSelect(mapping);
    };

    return (
        <PhotosFormDialog
            open={open}
            onClose={onClose}
            title={t("multi_folder_upload")}
            descriptionID={descriptionID}
        >
            <Typography id={descriptionID} sx={{ color: "text.muted" }}>
                {t("upload_to_choice")}
            </Typography>
            <Stack sx={{ gap: "12px" }}>
                <ButtonBase
                    sx={[mappingButtonSx, peopleActionFocusSx]}
                    onClick={() => handleSelect("root")}
                >
                    <HugeiconsIcon icon={Folder01Icon} size={20} aria-hidden />
                    {t("upload_to_single_album")}
                </ButtonBase>
                <ButtonBase
                    sx={[mappingButtonSx, peopleActionFocusSx]}
                    onClick={() => handleSelect("parent")}
                >
                    <HugeiconsIcon
                        icon={FolderLibraryIcon}
                        size={20}
                        aria-hidden
                    />
                    {t("upload_to_album_per_folder")}
                </ButtonBase>
            </Stack>
        </PhotosFormDialog>
    );
};

const mappingButtonSx = {
    ...v2SubmitButtonSx,
    flex: "none",
    height: "auto",
    minHeight: 52,
    p: "12px 16px",
    gap: "8px",
};
