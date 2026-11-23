import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import { IconButton, Tooltip } from "@mui/material";
import { t } from "i18next";
import { headerIconButtonSx } from "./header-styles";
import { usePhotosNavigation } from "./navigation/PhotosNavigationContext";

export const SectionBackButton = ({
    compact = true,
}: {
    compact?: boolean;
}) => {
    const { backToAlbums } = usePhotosNavigation();
    return (
        <Tooltip title={t("go_back")}>
            <IconButton
                aria-label={t("go_back")}
                onClick={backToAlbums}
                sx={
                    compact
                        ? { width: 32, height: 32, flexShrink: 0 }
                        : headerIconButtonSx
                }
            >
                <ArrowBackIcon sx={compact ? { fontSize: 20 } : undefined} />
            </IconButton>
        </Tooltip>
    );
};
