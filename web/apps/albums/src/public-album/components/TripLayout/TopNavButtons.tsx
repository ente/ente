import { LazyNotification } from "@/app/lazy/global-ui";
import { getEnteURL } from "@/public-album/access/utils/external-links";
import {
    AddPhotosIcon,
    DownloadIcon,
    FeedIcon,
    ShareIcon,
} from "@/public-album/components/ActionIcons";
import CheckIcon from "@mui/icons-material/Check";
import { Box, Button, IconButton, styled } from "@mui/material";
import { t } from "i18next";
import { useState } from "react";

interface TopNavButtonsProps {
    onAddPhotos?: () => void;
    downloadAllFiles: () => void;
    enableDownload?: boolean;
    onShowFeed?: () => void;
    enableJoin?: boolean;
    onJoinAlbum?: () => void;
}

export const TopNavButtons: React.FC<TopNavButtonsProps> = ({
    onAddPhotos,
    downloadAllFiles,
    enableDownload,
    onShowFeed,
}) => {
    const iconStrokeWidth = 1.8;
    const [showCopiedMessage, setShowCopiedMessage] = useState(false);

    const handleShare = () => {
        if (typeof window !== "undefined") {
            void navigator.clipboard.writeText(window.location.href);
            setShowCopiedMessage(true);
            setTimeout(() => setShowCopiedMessage(false), 2000);
        }
    };

    return (
        <>
            <ButtonContainer>
                <NavButton onClick={handleShare}>
                    <ShareIcon size={24} strokeWidth={iconStrokeWidth} />
                </NavButton>

                {onShowFeed && (
                    <NavButton onClick={onShowFeed}>
                        <FeedIcon size={24} strokeWidth={iconStrokeWidth} />
                    </NavButton>
                )}

                {onAddPhotos && (
                    <NavButton onClick={onAddPhotos}>
                        <AddPhotosIcon
                            size={24}
                            strokeWidth={iconStrokeWidth}
                        />
                    </NavButton>
                )}

                {enableDownload && (
                    <NavButton onClick={downloadAllFiles}>
                        <DownloadIcon size={24} strokeWidth={iconStrokeWidth} />
                    </NavButton>
                )}

                <SignUpButton
                    onClick={() => (window.location.href = getEnteURL())}
                >
                    {t("join_ente")}
                </SignUpButton>
            </ButtonContainer>

            {showCopiedMessage && (
                <LazyNotification
                    open={showCopiedMessage}
                    onClose={() => setShowCopiedMessage(false)}
                    horizontal="left"
                    attributes={{
                        color: "secondary",
                        startIcon: <CheckIcon />,
                        title: "Copied!",
                    }}
                />
            )}
        </>
    );
};

// Styled components
const ButtonContainer = styled(Box)({
    position: "fixed",
    top: "58px",
    right: "58px",
    display: "flex",
    gap: "8px",
    zIndex: 2000,
});

const NavButton = styled(IconButton)({
    padding: "12px",
    backgroundColor: "rgba(255, 255, 255, 0.9)",
    borderRadius: "8px",
    color: "#1f2937",
    transition: "background-color 0.2s",
    backdropFilter: "blur(10px)",
    boxShadow: "0 2px 8px rgba(0, 0, 0, 0.1)",
    width: "44px",
    height: "44px",
    "&:hover": { backgroundColor: "rgba(255, 255, 255, 1)" },
});

const SignUpButton = styled(Button)({
    padding: "12px 16px",
    marginLeft: "12px",
    fontSize: "16px",
    fontWeight: "600",
    whiteSpace: "nowrap",
    backgroundColor: "rgba(255, 255, 255, 0.9)",
    borderRadius: "8px",
    color: "#1f2937",
    transition: "background-color 0.2s",
    backdropFilter: "blur(10px)",
    boxShadow: "0 2px 8px rgba(0, 0, 0, 0.1)",
    "&:hover": { backgroundColor: "rgba(255, 255, 255, 1)" },
});
