import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import { Box, IconButton, Stack, Tooltip, Typography } from "@mui/material";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import { useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import { FixedSizeList, type ListChildComponentProps } from "react-window";
import { usePhotosNavigation } from "../../navigation/PhotosNavigationContext";
import { AlbumTile } from "./AlbumTile";

interface AlbumsHeaderProps {
    title: string;
    albums: CollectionSummary[];
    height: number;
    fileCount?: number;
}

export const albumsHeaderHeight = 311;

export const AlbumsHeader = ({
    title,
    albums,
    height,
    fileCount,
}: AlbumsHeaderProps) => {
    const { backToAlbums } = usePhotosNavigation();
    const [scrollOffset, setScrollOffset] = useState(0);

    return (
        <Stack sx={{ height, gap: "24px" }}>
            <Stack
                direction="row"
                sx={{ alignItems: "center", minHeight: 54, gap: 1 }}
            >
                <Tooltip title={t("go_back")}>
                    <IconButton
                        aria-label={t("go_back")}
                        onClick={backToAlbums}
                        sx={{ width: 32, height: 32 }}
                    >
                        <ArrowBackIcon sx={{ fontSize: 20 }} />
                    </IconButton>
                </Tooltip>
                <Box sx={{ minWidth: 0 }}>
                    <Typography
                        component="h2"
                        sx={{
                            fontFamily: '"Outfit Variable", Outfit, sans-serif',
                            fontWeight: 600,
                            fontSize: 24,
                            lineHeight: "32px",
                        }}
                    >
                        {title}
                    </Typography>
                    {fileCount !== undefined && (
                        <Typography
                            variant="small"
                            sx={{
                                color: "text.muted",
                                fontSize: 14,
                                fontWeight: 500,
                                lineHeight: "20px",
                                mt: "2px",
                            }}
                        >
                            {t("photos_count", { count: fileCount })}
                        </Typography>
                    )}
                </Box>
            </Stack>
            {albums.length > 0 && (
                <Box
                    sx={{
                        "--album-name-size": "14px",
                        "--album-count-size": "12px",
                        "--album-text-gap": "4px",
                        height: 200,
                        flexShrink: 0,
                    }}
                >
                    <AutoSizer disableHeight>
                        {({ width }) => (
                            <FixedSizeList
                                layout="horizontal"
                                width={width}
                                height={200}
                                itemCount={albums.length}
                                itemSize={162}
                                itemData={{ albums }}
                                itemKey={(index, data) =>
                                    data.albums[index]!.id
                                }
                                overscanCount={1}
                                useIsScrolling
                                onScroll={({ scrollOffset }) =>
                                    setScrollOffset(scrollOffset)
                                }
                                style={{
                                    overflowY: "hidden",
                                    maskImage:
                                        albums.length * 162 -
                                            width -
                                            scrollOffset >
                                        1
                                            ? "linear-gradient(to right, black calc(100% - 110px), transparent 100%)"
                                            : undefined,
                                }}
                            >
                                {HeaderAlbumTile}
                            </FixedSizeList>
                        )}
                    </AutoSizer>
                </Box>
            )}
        </Stack>
    );
};

const HeaderAlbumTile = ({
    index,
    style,
    data: { albums },
    isScrolling,
}: ListChildComponentProps<Pick<AlbumsHeaderProps, "albums">>) => {
    const { selectCollection } = usePhotosNavigation();
    const album = albums[index]!;
    return (
        <div style={style}>
            <AlbumTile
                album={album}
                onSelectAlbum={selectCollection}
                isScrolling={isScrolling}
                showBadges={false}
                countLabel={t("photos_count", { count: album.fileCount })}
            />
        </div>
    );
};
