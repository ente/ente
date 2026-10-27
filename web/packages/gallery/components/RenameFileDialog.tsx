import { Box, InputAdornment } from "@mui/material";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { nameAndExtension } from "ente-base/file-name";
import { t } from "i18next";

type RenameFileDialogProps = ModalVisibilityProps & {
    fileName: string;
    onRename: (newFileName: string) => Promise<void>;
};

export const RenameFileDialog: React.FC<RenameFileDialogProps> = ({
    open,
    onClose,
    fileName,
    onRename,
}) => {
    const [name, extension] = nameAndExtension(fileName);

    return (
        <SingleInputDialog
            {...{ open, onClose }}
            title={t("rename_file")}
            label={t("file_name")}
            placeholder={t("file_name")}
            initialValue={name}
            selectOnFocus
            submitButtonTitle={t("rename")}
            endAdornment={
                extension && (
                    <InputAdornment position="end">
                        <Box
                            component="span"
                            sx={{
                                fontSize: 13,
                                color: "text.muted",
                                borderLeft: "1px solid",
                                borderColor: "divider",
                                pl: 1.5,
                                ml: 1,
                            }}
                        >
                            {`.${extension}`}
                        </Box>
                    </InputAdornment>
                )
            }
            onSubmit={async (newName) => {
                const newFileName = [newName, extension]
                    .filter(Boolean)
                    .join(".");
                if (newFileName !== fileName) await onRename(newFileName);
            }}
        />
    );
};
