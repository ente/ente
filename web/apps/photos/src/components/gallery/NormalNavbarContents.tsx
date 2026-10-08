import { SearchBar, type SearchBarProps } from "@/components/SearchBar";
import { uploadManager } from "@/services/upload-manager";
import { Upload01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import MenuIcon from "@mui/icons-material/Menu";
import { Box, IconButton } from "@mui/material";
import { EnteLogo, EnteLogoBox } from "ente-base/components/EnteLogo";
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
    <Box
        sx={{
            position: "relative",
            display: "flex",
            alignItems: "center",
            flex: 1,
        }}
    >
        <SidebarButton onClick={onSidebar} />
        <EnteLogoBox
            sx={{
                position: "absolute",
                left: "50%",
                transform: "translateX(-50%)",
                pointerEvents: "none",
                "& svg": { height: { xs: "15px", sm: "20px" } },
            }}
        >
            <EnteLogo height={15} />
        </EnteLogoBox>
        <Box sx={{ flex: 1 }} />
        <SearchBar {...props} />
        <UploadButton onClick={onUpload} />
    </Box>
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
