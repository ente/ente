import { SearchBar, type SearchBarProps } from "@/components/SearchBar";
import { uploadManager } from "@/services/upload-manager";
import { Upload01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import MenuIcon from "@mui/icons-material/Menu";
import { IconButton } from "@mui/material";
import type { ButtonishProps } from "ente-base/components/mui";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import { t } from "i18next";

type NormalNavbarContentsProps = SearchBarProps & {
    onSidebar: () => void;
    onUpload: () => void;
};

export const NormalNavbarContents: React.FC<NormalNavbarContentsProps> = ({
    onSidebar,
    onUpload,
    ...props
}) => (
    <>
        <SidebarButton onClick={onSidebar} />
        <SearchBar {...props} />
        <UploadButton onClick={onUpload} />
    </>
);

const SidebarButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <IconButton {...{ onClick }}>
        <MenuIcon />
    </IconButton>
);

export const UploadButton: React.FC<ButtonishProps> = ({ onClick }) => {
    const disabled = uploadManager.isUploadInProgress();
    const isSmallWidth = useIsSmallWidth();

    const icon = <HugeiconsIcon icon={Upload01Icon} size={20} />;

    return (
        <>
            {isSmallWidth ? (
                <IconButton {...{ onClick, disabled }}>{icon}</IconButton>
            ) : (
                <FocusVisibleButton
                    color="secondary"
                    startIcon={icon}
                    sx={{ borderRadius: "16px" }}
                    {...{ onClick, disabled }}
                >
                    {t("upload")}
                </FocusVisibleButton>
            )}
        </>
    );
};
