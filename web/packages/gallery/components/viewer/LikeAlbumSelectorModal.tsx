import CloseIcon from "@mui/icons-material/Close";
import { Box, Dialog, IconButton, styled, Typography } from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { t } from "i18next";
import React from "react";

// =============================================================================
// Icons
// =============================================================================

const HeartFilledIcon: React.FC<{ size?: number; color?: string }> = ({
    size = 18,
    color = "#08C225",
}) => (
    <svg
        width={size}
        height={(size * 15) / 18}
        viewBox="0 0 18 15"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        style={{ display: "block" }}
    >
        <path
            d="M7.40825 13.8538C5.15122 12.1661 0.679688 8.30753 0.679688 4.83524C0.679688 2.54019 2.3639 0.679688 4.67969 0.679688C5.87969 0.679688 7.07969 1.07969 8.67969 2.67969C10.2797 1.07969 11.4797 0.679688 12.6797 0.679688C14.9954 0.679688 16.6797 2.54019 16.6797 4.83524C16.6797 8.30753 12.2082 12.1661 9.95113 13.8538C9.19161 14.4218 8.16777 14.4218 7.40825 13.8538Z"
            fill={color}
            stroke={color}
            strokeWidth="1.36"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
    </svg>
);

const HeartOutlineIcon: React.FC<{ size?: number; color?: string }> = ({
    size = 18,
    color = "#08C225",
}) => (
    <svg
        width={size}
        height={(size * 15) / 18}
        viewBox="0 0 18 15"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        style={{ display: "block" }}
    >
        <path
            d="M7.40825 13.8538C5.15122 12.1661 0.679688 8.30753 0.679688 4.83524C0.679688 2.54019 2.3639 0.679688 4.67969 0.679688C5.87969 0.679688 7.07969 1.07969 8.67969 2.67969C10.2797 1.07969 11.4797 0.679688 12.6797 0.679688C14.9954 0.679688 16.6797 2.54019 16.6797 4.83524C16.6797 8.30753 12.2082 12.1661 9.95113 13.8538C9.19161 14.4218 8.16777 14.4218 7.40825 13.8538Z"
            stroke={color}
            strokeWidth="1.36"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
    </svg>
);

const LikePhotoIllustration: React.FC = () => (
    <svg
        width="126"
        height="121"
        viewBox="0 0 126 121"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M84.7129 23.0781C96.7222 23.0784 105.29 32.8476 105.29 44.499C105.29 53.3449 99.7258 62.2116 93.4453 69.4932C87.0622 76.8936 79.4391 83.2238 74.3574 87.0557C69.973 90.3616 64.031 90.3614 59.6465 87.0557C54.5648 83.2238 46.9408 76.8937 40.5576 69.4932C34.2771 62.2116 28.7129 53.3449 28.7129 44.499C28.713 32.8474 37.2813 23.0781 49.291 23.0781C54.9545 23.0782 60.4297 24.9062 67.001 30.9004C73.5726 24.9056 79.0491 23.0781 84.7129 23.0781Z"
            fill="#08C225"
            stroke="#232323"
            strokeWidth="5.73358"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
        <mask
            id="mask0_643_19218"
            style={{ maskType: "alpha" }}
            maskUnits="userSpaceOnUse"
            x="31"
            y="25"
            width="72"
            height="62"
        >
            <path
                d="M61.3721 84.7662C51.3787 77.2306 31.5801 60.0026 31.5801 44.4993C31.5801 34.2522 39.0372 25.9453 49.2909 25.9453C54.6041 25.9453 59.9173 27.7313 67.0016 34.8751C74.086 27.7313 79.3992 25.9453 84.7124 25.9453C94.9659 25.9453 102.423 34.2522 102.423 44.4993C102.423 60.0026 82.6247 77.2306 72.6312 84.7662C69.2683 87.3019 64.735 87.3019 61.3721 84.7662Z"
                fill="#08C225"
            />
        </mask>
        <g mask="url(#mask0_643_19218)">
            <path
                d="M47.5975 41.0431C46.8515 39.3306 47.9859 37.1849 50.1312 36.2504C52.2765 35.316 54.6203 35.9467 55.3662 37.6591C56.1121 39.3716 54.9777 41.5173 52.8324 42.4518C50.6872 43.3862 48.3434 42.7555 47.5975 41.0431Z"
                fill="white"
            />
            <path
                d="M44.5677 45.0545C44.3136 44.4712 44.7025 43.7391 45.4364 43.4194C46.1704 43.0997 46.9713 43.3135 47.2254 43.8968C47.4795 44.4802 47.0906 45.2123 46.3567 45.532C45.6227 45.8517 44.8218 45.6379 44.5677 45.0545Z"
                fill="white"
            />
            <path
                d="M102.994 32.271C101.622 55.1395 78.9821 78.0073 50.9683 82.581C49.2531 88.2982 42.3926 93.7861 42.3926 95.1582C42.3926 96.5303 48.1097 107.926 50.9683 113.453L89.8447 101.447L115 66.5725C113.094 57.9969 106.196 31.3563 102.994 32.271Z"
                fill="#46A030"
            />
            <path
                d="M59.7039 28.2666C34.9591 23.1218 29.8137 47.7054 32.6723 55.1377L23.1143 51.7074C21.3992 47.3243 18.1976 37.9863 19.1123 35.6995C20.0271 33.4126 22.1615 16.833 23.1143 8.829L55.1302 3.68359L96.8651 13.9744C97.6274 18.1664 98.4659 26.8936 95.7217 28.2666C80.2855 22.5506 66.5644 33.9826 66.5644 33.4109C66.5644 32.9535 68.4701 30.5523 69.423 29.4089C66.3738 29.0281 60.1612 28.2666 59.7039 28.2666Z"
                fill="white"
            />
        </g>
        <path
            d="M20.9639 58.8477C14.9399 61.182 10.9104 66.0874 11.263 71.48C10.9104 66.0874 6.28324 61.7544 -9.80907e-05 60.2184C6.02383 57.884 10.0533 52.9787 9.70073 47.5861C10.0533 52.9787 14.6805 57.3117 20.9639 58.8477Z"
            fill="#08C225"
        />
        <path
            d="M119.579 91.9746C111.591 92.7003 105.114 97.1692 103.689 103.722C105.114 97.1692 101.077 90.4145 94.1117 86.438C102.099 85.7122 108.576 81.2434 110.001 74.6902C108.576 81.2434 112.613 87.9981 119.579 91.9746Z"
            fill="#08C225"
        />
        <path
            d="M112.728 9.21189C108.334 9.91374 104.912 12.6353 104.37 16.3181C104.912 12.6353 102.421 9.04853 98.4114 7.10627C102.806 6.40442 106.228 3.68284 106.77 7.55054e-05C106.228 3.68284 108.719 7.26962 112.728 9.21189Z"
            fill="#08C225"
        />
    </svg>
);

// =============================================================================
// Types
// =============================================================================

interface Album {
    id: number;
    name: string;
    coverURL?: string;
}

export interface LikeAlbumSelectorModalProps extends ModalVisibilityProps {
    /**
     * List of albums containing this file that user can like in.
     */
    albums: Album[];
    /**
     * Set of album IDs where the photo is currently liked.
     */
    likedAlbumIDs: Set<number>;
    /**
     * Called when user clicks on an album to toggle like status.
     * @param albumId The album ID
     * @param isCurrentlyLiked Whether the album is currently liked
     */
    onToggleAlbum: (albumId: number, isCurrentlyLiked: boolean) => void;
    /**
     * Called when user clicks "Like all" to like in all albums.
     */
    onLikeAll: () => void;
}

/**
 * Modal dialog for selecting which album to like a photo in.
 * Shown when the like button is clicked and the photo was opened from
 * gallery view (not from a specific collection).
 */
export const LikeAlbumSelectorModal: React.FC<LikeAlbumSelectorModalProps> = ({
    open,
    onClose,
    albums,
    likedAlbumIDs,
    onToggleAlbum,
    onLikeAll,
}) => {
    const likedCount = likedAlbumIDs.size;
    const allLiked = likedCount === albums.length && albums.length > 0;

    return (
        <StyledDialog open={open} onClose={onClose}>
            <DialogWrapper>
                <CloseButton onClick={onClose}>
                    <CloseIcon sx={{ fontSize: 20 }} />
                </CloseButton>

                <ContentContainer>
                    <IllustrationWrapper>
                        <LikePhotoIllustration />
                    </IllustrationWrapper>

                    <TitleSection>
                        <Title>{t("like_photo")}</Title>
                        <Subtitle>{t("select_album_to_like")}</Subtitle>
                    </TitleSection>

                    <AlbumsSection>
                        <AlbumsHeader>
                            <AlbumsCount>
                                {t("albums_count", { count: albums.length })}
                            </AlbumsCount>
                            <LikeAllButton
                                onClick={!allLiked ? onLikeAll : undefined}
                                sx={{
                                    opacity: !allLiked ? 1 : 0.5,
                                    cursor: !allLiked ? "pointer" : "default",
                                    pointerEvents: !allLiked ? "auto" : "none",
                                }}
                            >
                                <Typography
                                    sx={(theme) => ({
                                        fontWeight: 500,
                                        fontSize: 14,
                                        color: "#000",
                                        ...theme.applyStyles("dark", {
                                            color: "#fff",
                                        }),
                                    })}
                                >
                                    {t("like_all")}
                                </Typography>
                                {allLiked ? (
                                    <HeartFilledIcon
                                        size={16}
                                        color="var(--mui-palette-text-base)"
                                    />
                                ) : (
                                    <HeartOutlineIcon
                                        size={16}
                                        color="var(--mui-palette-text-base)"
                                    />
                                )}
                            </LikeAllButton>
                        </AlbumsHeader>

                        <AlbumsList>
                            {albums.map((album) => {
                                const isLiked = likedAlbumIDs.has(album.id);
                                return (
                                    <AlbumItem key={album.id}>
                                        <AlbumName>{album.name}</AlbumName>
                                        <HeartButton
                                            onClick={() =>
                                                onToggleAlbum(album.id, isLiked)
                                            }
                                        >
                                            {isLiked ? (
                                                <HeartFilledIcon />
                                            ) : (
                                                <HeartOutlineIcon />
                                            )}
                                        </HeartButton>
                                    </AlbumItem>
                                );
                            })}
                        </AlbumsList>
                    </AlbumsSection>
                </ContentContainer>
            </DialogWrapper>
        </StyledDialog>
    );
};

// =============================================================================
// Styled Components
// =============================================================================

const StyledDialog = styled(Dialog)(({ theme }) => ({
    "& .MuiDialog-paper": {
        width: 381,
        maxWidth: "calc(100% - 32px)",
        borderRadius: 28,
        backgroundColor: "#fff",
        padding: 0,
        margin: 16,
        overflow: "visible",
        boxShadow: "none",
        border: "1px solid #E0E0E0",
        ...theme.applyStyles("dark", {
            backgroundColor: "#1b1b1b",
            border: "1px solid rgba(255, 255, 255, 0.18)",
        }),
    },
    "& .MuiBackdrop-root": { backgroundColor: "rgba(0, 0, 0, 0.5)" },
}));

const DialogWrapper = styled(Box)(() => ({
    position: "relative",
    padding: "58px 24px 24px 24px",
}));

const CloseButton = styled(IconButton)(({ theme }) => ({
    position: "absolute",
    top: 11,
    right: 12,
    backgroundColor: "#FAFAFA",
    color: "#000",
    padding: 10,
    "&:hover": { backgroundColor: "#F0F0F0" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255, 255, 255, 0.12)",
        color: "#fff",
        "&:hover": { backgroundColor: "rgba(255, 255, 255, 0.16)" },
    }),
}));

const ContentContainer = styled(Box)(() => ({
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: 16,
}));

const IllustrationWrapper = styled(Box)(() => ({
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    marginBottom: -12,
}));

const TitleSection = styled(Box)(() => ({
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: 9,
    textAlign: "center",
    marginBottom: 14,
}));

const Title = styled(Typography)(({ theme }) => ({
    fontWeight: 600,
    fontSize: 24,
    lineHeight: "22px",
    letterSpacing: "-0.48px",
    color: "#000",
    ...theme.applyStyles("dark", { color: "#fff" }),
}));

const Subtitle = styled(Typography)(({ theme }) => ({
    fontWeight: 500,
    fontSize: 14,
    lineHeight: "17px",
    color: "#666666",
    maxWidth: 295,
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.7)" }),
}));

const AlbumsSection = styled(Box)(({ theme }) => ({
    width: "100%",
    backgroundColor: "rgba(162, 162, 162, 0.12)",
    borderRadius: 27,
    padding: "16px 0 0 0",
    maxHeight: 313,
    display: "flex",
    flexDirection: "column",
    overflow: "hidden",
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(162, 162, 162, 0.12)",
    }),
}));

const AlbumsHeader = styled(Box)(() => ({
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    padding: "0 16px 0 25px",
    marginBottom: 16,
}));

const AlbumsCount = styled(Typography)(({ theme }) => ({
    fontWeight: 500,
    fontSize: 14,
    lineHeight: "17px",
    color: "#000",
    ...theme.applyStyles("dark", { color: "#fff" }),
}));

const LikeAllButton = styled(Box)(({ theme }) => ({
    display: "flex",
    alignItems: "center",
    gap: 10,
    padding: 10,
    backgroundColor: "#fff",
    borderRadius: 14,
    cursor: "pointer",
    "&:hover": { backgroundColor: "#EBEBEB" },
    ...theme.applyStyles("dark", {
        backgroundColor: "#1b1b1b",
        "&:hover": { backgroundColor: "#252525" },
    }),
}));

const AlbumsList = styled(Box)(({ theme }) => ({
    display: "flex",
    flexDirection: "column",
    gap: 6,
    padding: "0 12px 12px 12px",
    overflowY: "auto",
    maxHeight: 241,
    "&::-webkit-scrollbar": { width: 6 },
    "&::-webkit-scrollbar-track": { background: "transparent" },
    "&::-webkit-scrollbar-thumb": {
        background: "rgba(0, 0, 0, 0.2)",
        borderRadius: 3,
    },
    ...theme.applyStyles("dark", {
        "&::-webkit-scrollbar-thumb": {
            background: "rgba(255, 255, 255, 0.2)",
        },
    }),
}));

const AlbumItem = styled(Box)(({ theme }) => ({
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
    padding: "10px 10px 10px 16px",
    backgroundColor: "#fff",
    borderRadius: 16,
    ...theme.applyStyles("dark", { backgroundColor: "#212121" }),
}));

const AlbumName = styled(Typography)(({ theme }) => ({
    fontWeight: 500,
    fontSize: 14,
    lineHeight: "17px",
    color: "#000",
    flex: 1,
    ...theme.applyStyles("dark", { color: "#fff" }),
}));

const HeartButton = styled(Box)(() => ({
    width: 32,
    height: 32,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "rgba(8, 194, 37, 0.06)",
    borderRadius: 9.6,
    cursor: "pointer",
    "&:hover": { backgroundColor: "rgba(8, 194, 37, 0.12)" },
}));
