import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import { Box, IconButton, Stack, Tooltip, Typography } from "@mui/material";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import { useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import { FixedSizeList, type ListChildComponentProps } from "react-window";
import { AlbumTile } from "./AlbumTile";

interface AlbumsHeaderProps {
    title: string;
    albums: CollectionSummary[];
    onSelectAlbum: (id: number) => void;
    onBack: () => void;
}

export const albumsHeaderHeight = 311;

export const AlbumsHeader = ({
    title,
    albums,
    onSelectAlbum,
    onBack,
}: AlbumsHeaderProps) => {
    const [scrollOffset, setScrollOffset] = useState(0);

    return (
        <Stack
            sx={{
                height: albums.length ? albumsHeaderHeight : 78,
                gap: "24px",
            }}
        >
            <Stack
                direction="row"
                sx={{ alignItems: "center", minHeight: 54, gap: 1 }}
            >
                <Tooltip title={t("go_back")}>
                    <IconButton
                        aria-label={t("go_back")}
                        onClick={onBack}
                        sx={{ width: 32, height: 32 }}
                    >
                        <ArrowBackIcon sx={{ fontSize: 20 }} />
                    </IconButton>
                </Tooltip>
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
                                itemData={{ albums, onSelectAlbum }}
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
    data: { albums, onSelectAlbum },
    isScrolling,
}: ListChildComponentProps<
    Pick<AlbumsHeaderProps, "albums" | "onSelectAlbum">
>) => {
    const album = albums[index]!;
    return (
        <div style={style}>
            <AlbumTile
                album={album}
                onSelectAlbum={onSelectAlbum}
                isScrolling={isScrolling}
                showBadges={false}
                countLabel={t("photos_count", { count: album.fileCount })}
            />
        </div>
    );
};
