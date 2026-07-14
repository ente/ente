import { ImageAdd02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import FileDownloadIcon from "@mui/icons-material/FileDownloadOutlined";
import { Paper, Stack, styled, Typography } from "@mui/material";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import type { UploadTypeSelectorIntent } from "ente-gallery/components/Upload";
import { t } from "i18next";
import React from "react";
import { Trans } from "react-i18next";

interface GalleryEmptyStateV2Props {
    /**
     * If `true`, then an upload is already in progress (the empty state will
     * then disable the prompts for uploads).
     */
    isUploadInProgress: boolean;
    /**
     * Called when the user selects one of the upload buttons. It is passed the
     * "intent" of the user.
     */
    onUpload: (intent: UploadTypeSelectorIntent) => void;
}

const galleryEmptyStateShelfTiles = Array.from({ length: 20 }, (_, i) => i);
const galleryEmptyStateGridTiles = Array.from({ length: 56 }, (_, i) => i);

export function GalleryEmptyStateV2({
    isUploadInProgress,
    onUpload,
}: GalleryEmptyStateV2Props): React.JSX.Element {
    const handleImport = () => onUpload("import");
    const handleUpload = () => onUpload("upload");

    return (
        <Stack
            sx={{
                flex: 1,
                position: "relative",
                width: "100%",
                height: "100%",
                minHeight: 0,
                maxHeight: "100%",
                alignItems: "center",
                justifyContent: "center",
                overflow: "hidden",
                boxSizing: "border-box",
                px: { xs: 2, md: 3 },
                bgcolor: "background.default",
            }}
        >
            <GalleryEmptyStateSkeleton />
            <GalleryEmptyStateSkeletonOverlay />
            <Paper
                elevation={0}
                sx={{
                    position: "relative",
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    width: "min(600px, 100%)",
                    height: { xs: 428, sm: 512 },
                    flexShrink: 0,
                    mt: { xs: "72px", sm: "88px" },
                    transform: "translateY(-16px)",
                    px: { xs: 2.5, sm: 4 },
                    pt: { xs: "150px", sm: "232px" },
                    pb: { xs: 4, sm: "44px" },
                    borderRadius: { xs: "30px", sm: "42px" },
                    bgcolor: "background.paper",
                    zIndex: 2,
                }}
            >
                <NonDraggableImage
                    alt=""
                    src="/images/empty-state/ente_empty_state_figma.svg"
                />

                <Stack
                    sx={{
                        alignItems: "center",
                        gap: "24px",
                        mt: { xs: "6px", sm: "8px" },
                        textAlign: "center",
                        userSelect: "none",
                    }}
                >
                    <Typography
                        variant="h3"
                        sx={{
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            gap: { xs: "6px", sm: "8px" },
                            color: "text.base",
                            fontFamily: "'Outfit', sans-serif",
                            fontSize: { xs: "26px", sm: "34px" },
                            lineHeight: { xs: "20px", sm: "26px" },
                            fontWeight: 700,
                            svg: {
                                color: "text.base",
                                height: { xs: 18, sm: "22.592px" },
                                width: { xs: 61, sm: 76 },
                                flexShrink: 0,
                                transform: {
                                    xs: "translateY(1px)",
                                    sm: "translateY(2px)",
                                },
                            },
                        }}
                    >
                        <Trans
                            i18nKey="welcome_to_ente_title"
                            components={{ a: <EnteLogo /> }}
                        />
                    </Typography>
                    <Typography
                        variant="h6"
                        sx={{
                            color: "text.base",
                            fontFamily: "'Inter Variable', 'Inter', sans-serif",
                            fontSize: { xs: "16px", sm: "20px" },
                            lineHeight: { xs: "18px", sm: "20px" },
                            fontWeight: 600,
                        }}
                    >
                        Store and share your memories with full privacy
                    </Typography>
                </Stack>

                <Stack
                    sx={{ mt: "40px", width: 334, maxWidth: "100%", gap: 1 }}
                >
                    <GalleryEmptyStateButton
                        color="accent"
                        onClick={handleImport}
                        disabled={isUploadInProgress}
                        startIcon={<FileDownloadIcon />}
                    >
                        Import your existing library
                    </GalleryEmptyStateButton>
                    <GalleryEmptyStateButton
                        color="secondary"
                        onClick={handleUpload}
                        disabled={isUploadInProgress}
                        startIcon={
                            <HugeiconsIcon
                                icon={ImageAdd02Icon}
                                size={20}
                                strokeWidth={2}
                            />
                        }
                    >
                        {t("upload_first_photo")}
                    </GalleryEmptyStateButton>
                </Stack>
            </Paper>
        </Stack>
    );
}

function GalleryEmptyStateSkeleton(): React.JSX.Element {
    return (
        <GalleryEmptyStateSkeletonRoot aria-hidden>
            <div className="skeleton-albums">
                <span className="skeleton-label skeleton-label-wide" />
                <div className="skeleton-shelf">
                    {galleryEmptyStateShelfTiles.map((tile) => (
                        <span key={tile} />
                    ))}
                </div>
            </div>
            <div className="skeleton-gallery">
                <div className="skeleton-title-group">
                    <span className="skeleton-label skeleton-label-short" />
                    <span className="skeleton-label skeleton-label-wide" />
                </div>
                <span className="skeleton-label skeleton-label-short" />
                <div className="skeleton-grid">
                    {galleryEmptyStateGridTiles.map((tile) => (
                        <span key={tile} />
                    ))}
                </div>
            </div>
        </GalleryEmptyStateSkeletonRoot>
    );
}

const GalleryEmptyStateSkeletonRoot = styled("div")(({ theme }) => {
    const fill = theme.vars.palette.fill.faintHover;

    return {
        position: "absolute",
        inset: 0,
        zIndex: 0,
        overflow: "hidden",
        pointerEvents: "none",
        padding: "24px",
        boxSizing: "border-box",
        display: "flex",
        flexDirection: "column",
        ".skeleton-albums": { marginTop: 0 },
        ".skeleton-gallery": {
            display: "flex",
            flex: 1,
            flexDirection: "column",
            minHeight: 0,
            marginTop: 28,
        },
        ".skeleton-title-group": {
            display: "flex",
            flexDirection: "column",
            gap: 9,
            marginBottom: 28,
            width: 102,
        },
        ".skeleton-label": {
            display: "block",
            height: 18,
            borderRadius: 2,
            background: fill,
        },
        ".skeleton-label-short": { width: 53 },
        ".skeleton-label-wide": { width: 89 },
        ".skeleton-shelf": {
            display: "grid",
            gridTemplateColumns: "repeat(20, minmax(98px, 1fr))",
            gap: 4,
            marginTop: 8,
            width: "100%",
        },
        ".skeleton-shelf > span": {
            height: 71,
            borderRadius: 2,
            background: fill,
        },
        ".skeleton-grid": {
            display: "grid",
            flex: 1,
            gridTemplateColumns: "repeat(auto-fill, minmax(198px, 1fr))",
            gridAutoRows: "minmax(160px, 1fr)",
            gap: 4,
            marginTop: 11,
            minHeight: 0,
            width: "100%",
        },
        ".skeleton-grid > span": { borderRadius: 4, background: fill },
        [theme.breakpoints.down("md")]: {
            ".skeleton-grid": {
                gridTemplateColumns: "repeat(auto-fill, minmax(160px, 1fr))",
            },
        },
        [theme.breakpoints.down("sm")]: {
            padding: "20px 16px",
            ".skeleton-shelf": {
                gridTemplateColumns: "repeat(20, minmax(84px, 1fr))",
            },
            ".skeleton-grid": {
                gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
                gridAutoRows: "minmax(110px, 1fr)",
            },
        },
    };
});

const GalleryEmptyStateSkeletonOverlay = styled("div")(({ theme }) => ({
    position: "absolute",
    inset: 0,
    zIndex: 1,
    pointerEvents: "none",
    opacity: 0.72,
    background: theme.vars.palette.background.default,
}));

const GalleryEmptyStateButton = styled(FocusVisibleButton)(({ theme }) => ({
    height: 52,
    borderRadius: 20,
    paddingBlock: 14,
    paddingInline: 24,
    fontSize: theme.typography.small.fontSize,
    lineHeight: "20px",
    fontWeight: theme.typography.fontWeightMedium,
    "&.MuiButton-containedAccent:not(.Mui-disabled)": {
        backgroundColor: "#08C225",
        "&:hover": { backgroundColor: "#08C225" },
    },
    "& .MuiButton-startIcon": { marginRight: 8, "& > svg": { fontSize: 20 } },
}));

/**
 * Prevent the image from being selected _and_ dragged, since dragging it
 * triggers the our dropdown selector overlay.
 */
const NonDraggableImage = styled("img")(({ theme }) => ({
    position: "absolute",
    top: -96,
    width: 310,
    maxWidth: "calc(100% - 48px)",
    aspectRatio: "351 / 305.183",
    height: "auto",
    pointerEvents: "none",
    userSelect: "none",
    [theme.breakpoints.down("sm")]: { top: -80, width: 264 },
}));
