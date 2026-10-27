import { PinIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Stack, Typography, styled } from "@mui/material";
import { ItemCard } from "ente-new/photos/components/Tiles";
import { UnstyledButton } from "ente-new/photos/components/UnstyledButton";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { t } from "i18next";

interface AlbumTileProps {
    album: CollectionSummary;
    onSelectAlbum: (id: number) => void;
    isScrolling?: boolean;
    isLinks?: boolean;
    countLabel?: string;
    showBadges?: boolean;
}

export const AlbumTile = ({
    album,
    onSelectAlbum,
    isScrolling,
    isLinks,
    countLabel,
    showBadges = true,
}: AlbumTileProps) => {
    const badge = album.attributes.has("sharedIncoming")
        ? t("album_overview_received_title")
        : album.attributes.has("sharedOutgoing") ||
            album.attributes.has("sharedViaLink")
          ? t("shared_albums_label")
          : undefined;
    return (
        <AlbumTileButton
            title={album.name}
            onClick={() => onSelectAlbum(album.id)}
        >
            <ItemCard
                TileComponent={AlbumTileCover}
                coverFile={album.coverFile}
                isScrolling={isScrolling}
            >
                {showBadges && !isLinks && badge && (
                    <Box
                        component="span"
                        sx={{
                            position: "absolute",
                            right: 8,
                            bottom: 8,
                            height: 24,
                            px: "8px",
                            borderRadius: "8px",
                            bgcolor: "rgba(0,0,0,.55)",
                            color: "#fff",
                            fontSize: 11,
                            fontWeight: 600,
                            display: "flex",
                            alignItems: "center",
                            backdropFilter: "blur(6px)",
                            maxWidth: "calc(100% - 16px)",
                            overflow: "hidden",
                            whiteSpace: "nowrap",
                        }}
                    >
                        {badge}
                    </Box>
                )}
            </ItemCard>
            <Stack
                component="span"
                sx={{ width: "100%", gap: "var(--album-text-gap, 2px)" }}
            >
                <Stack
                    component="span"
                    direction="row"
                    sx={{ alignItems: "center", gap: "4px", minWidth: 0 }}
                >
                    <Typography
                        component="span"
                        noWrap
                        sx={{
                            fontSize: "var(--album-name-size)",
                            lineHeight: "20px",
                            fontWeight: 500,
                        }}
                    >
                        {album.name}
                    </Typography>
                    {showBadges &&
                        (album.attributes.has("pinned") ||
                            album.attributes.has("shareePinned")) && (
                            <Box
                                component={HugeiconsIcon}
                                icon={PinIcon}
                                size={12}
                                sx={{ flexShrink: 0, color: "text.faint" }}
                            />
                        )}
                </Stack>
                <Typography
                    component="span"
                    sx={{
                        fontSize: "var(--album-count-size)",
                        lineHeight: "16px",
                        fontWeight: 500,
                        color: "text.muted",
                    }}
                >
                    {countLabel ??
                        t("album_items_count", { count: album.fileCount })}
                </Typography>
            </Stack>
        </AlbumTileButton>
    );
};

export const AlbumTileButton = styled(UnstyledButton)(({ theme }) => ({
    width: "var(--album-tile-width, 140px)",
    flexShrink: 0,
    display: "flex",
    flexDirection: "column",
    alignItems: "flex-start",
    gap: 8,
    color: theme.vars.palette.text.base,
    textAlign: "left",
    borderRadius: 20,
    "&:hover": { opacity: 0.86 },
    "&:focus-visible": {
        outline: `2px solid ${theme.vars.palette.stroke.base}`,
        outlineOffset: -2,
    },
}));

export const AlbumTileCover = styled("div")({
    width: "var(--album-tile-width, 140px)",
    height: "var(--album-tile-width, 140px)",
    flexShrink: 0,
    borderRadius: 20,
    overflow: "hidden",
    position: "relative",
    "& > img": {
        width: "100%",
        height: "100%",
        objectFit: "cover",
        display: "block",
    },
});
