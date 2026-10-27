import { useDeleteEmptyAlbums } from "@/components/collections/useDeleteEmptyAlbums";
import type { RemotePullOpts } from "@/components/gallery";
import type { AlbumFilter } from "@/utils/album-filters";
import { Delete02Icon, ImageAdd02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    IconButton,
    Stack,
    Tooltip,
    Typography,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import type {
    CollectionSummary,
    CollectionsSortBy,
} from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import { useEffect, useRef, useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import { FixedSizeList, type ListChildComponentProps } from "react-window";
import {
    AlbumTileButton as AlbumButton,
    AlbumTile,
    AlbumTileCover as Cover,
} from "./AlbumTile";

interface AlbumsOverviewProps {
    albums: CollectionSummary[];
    title: string;
    filter: AlbumFilter | "links";
    searchQuery: string;
    sortBy: CollectionsSortBy;
    onSelectAlbum: (id: number) => void;
    onCreateAlbum: () => void;
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
}

export const AlbumsOverview = ({
    albums,
    title,
    filter,
    searchQuery,
    sortBy,
    onSelectAlbum,
    onCreateAlbum,
    onRemotePull,
}: AlbumsOverviewProps) => {
    const compact = useMediaQuery(useTheme().breakpoints.down("md"));
    const listRef = useRef<FixedSizeList>(null);
    const [listElement, setListElement] = useState<HTMLDivElement | null>(null);
    const [scrollbarWidth, setScrollbarWidth] = useState(0);
    useEffect(() => {
        if (!listElement) return;
        const measure = () =>
            setScrollbarWidth(
                listElement.offsetWidth - listElement.clientWidth,
            );
        measure();
        const observer = new ResizeObserver(measure);
        observer.observe(listElement);
        return () => observer.disconnect();
    }, [listElement]);
    const normalizedSearchQuery = searchQuery.trim().toLowerCase();
    const { handleDeleteEmptyAlbums, hasEnoughEmptyAlbums } =
        useDeleteEmptyAlbums(albums, onRemotePull);
    const showDeleteEmptyAlbums =
        filter == "empty-albums" &&
        hasEnoughEmptyAlbums &&
        !normalizedSearchQuery;
    const showCreate = filter == "ente" && !normalizedSearchQuery;
    const tileWidth = compact ? 104 : 140;
    const columnGap = compact ? 12 : 22;
    const rowGap = compact ? 16 : 24;
    const cardHeight = tileWidth + 8 + 20 + 2 + 16;
    const isLinks = filter == "links";
    const displayTitle =
        filter == "shared"
            ? t("album_overview_shared_title")
            : filter == "received"
              ? t("album_overview_received_title")
              : title;

    useEffect(() => {
        listRef.current?.scrollTo(0);
    }, [filter, normalizedSearchQuery, sortBy]);

    return (
        <>
            <Stack
                sx={{
                    flex: 1,
                    minHeight: 0,
                    overflow: "hidden",
                    px: { xs: "14px", md: "24px" },
                    pb: { xs: "16px", md: "36px" },
                    gap: "24px",
                }}
            >
                <Stack
                    sx={{
                        flexShrink: 0,
                        minHeight: 54,
                        flexDirection: "row",
                        alignItems: "center",
                        justifyContent: "space-between",
                        flexWrap: "wrap",
                        gap: 2,
                    }}
                >
                    <Stack sx={{ minWidth: 0, gap: "2px" }}>
                        <Typography
                            component="h1"
                            sx={{
                                fontFamily:
                                    '"Outfit Variable", Outfit, sans-serif',
                                fontSize: { xs: 20, md: 24 },
                                lineHeight: { xs: "26px", md: "32px" },
                                fontWeight: 600,
                            }}
                        >
                            {displayTitle}
                        </Typography>
                        <Typography
                            sx={{
                                fontSize: { xs: 12, md: 14 },
                                lineHeight: "20px",
                                color: "text.muted",
                            }}
                        >
                            {t(
                                isLinks
                                    ? "links_count"
                                    : "album_overview_count",
                                { count: albums.length },
                            )}
                        </Typography>
                    </Stack>
                    {showDeleteEmptyAlbums && (
                        <Tooltip title={t("delete_empty_albums")}>
                            <IconButton
                                aria-label={t("delete_empty_albums")}
                                onClick={handleDeleteEmptyAlbums}
                                sx={{
                                    flexShrink: 0,
                                    marginInlineStart: "auto",
                                }}
                            >
                                <HugeiconsIcon
                                    icon={Delete02Icon}
                                    size={22}
                                    strokeWidth={1.5}
                                />
                            </IconButton>
                        </Tooltip>
                    )}
                </Stack>
                {!albums.length && !showCreate ? (
                    <Typography
                        role="status"
                        sx={{ color: "text.muted", fontSize: 14 }}
                    >
                        {t("no_results")}
                    </Typography>
                ) : (
                    <Box
                        sx={{
                            flex: 1,
                            minHeight: 0,
                            "--album-tile-width": `${tileWidth}px`,
                            "--album-name-size": compact ? "13px" : "14px",
                            "--album-count-size": compact ? "11px" : "12px",
                        }}
                    >
                        <AutoSizer>
                            {({ width, height }) => {
                                const columns = Math.max(
                                    1,
                                    Math.floor(
                                        (width - scrollbarWidth + columnGap) /
                                            (tileWidth + columnGap),
                                    ),
                                );
                                return (
                                    <FixedSizeList
                                        ref={listRef}
                                        outerRef={setListElement}
                                        width={width}
                                        height={height}
                                        itemCount={Math.ceil(
                                            (albums.length +
                                                Number(showCreate)) /
                                                columns,
                                        )}
                                        itemSize={cardHeight + rowGap}
                                        overscanCount={1}
                                        useIsScrolling
                                        style={{ overflowX: "hidden" }}
                                        itemData={{
                                            albums,
                                            isLinks,
                                            columns,
                                            columnGap,
                                            tileWidth,
                                            showCreate,
                                            onSelectAlbum,
                                            onCreateAlbum,
                                        }}
                                    >
                                        {AlbumsRow}
                                    </FixedSizeList>
                                );
                            }}
                        </AutoSizer>
                    </Box>
                )}
            </Stack>
        </>
    );
};

interface AlbumRowData {
    isLinks: boolean;
    albums: CollectionSummary[];
    columns: number;
    columnGap: number;
    tileWidth: number;
    showCreate: boolean;
    onSelectAlbum: (id: number) => void;
    onCreateAlbum: () => void;
}

const AlbumsRow = ({
    data,
    index,
    style,
    isScrolling,
}: ListChildComponentProps<AlbumRowData>) => {
    const start = index * data.columns;
    const end = Math.min(
        start + data.columns,
        data.albums.length + Number(data.showCreate),
    );
    return (
        <div
            style={{
                ...style,
                display: "grid",
                gridTemplateColumns: `repeat(${data.columns}, ${data.tileWidth}px)`,
                columnGap: data.columnGap,
                alignItems: "start",
            }}
        >
            {Array.from({ length: end - start }, (_, offset) => {
                const itemIndex = start + offset;
                if (data.showCreate && itemIndex === 0)
                    return (
                        <AlbumButton
                            key="create"
                            aria-label={t("new_album")}
                            onClick={data.onCreateAlbum}
                        >
                            <Cover
                                sx={{
                                    bgcolor: "fill.faint",
                                    color: "text.muted",
                                    display: "flex",
                                    alignItems: "center",
                                    justifyContent: "center",
                                }}
                            >
                                <HugeiconsIcon
                                    icon={ImageAdd02Icon}
                                    size={32}
                                    strokeWidth={1.5}
                                    aria-hidden
                                />
                            </Cover>
                            <Typography
                                component="span"
                                sx={{
                                    fontSize: "var(--album-name-size)",
                                    lineHeight: "20px",
                                    fontWeight: 500,
                                }}
                            >
                                {t("new_album")}
                            </Typography>
                        </AlbumButton>
                    );
                const album = data.albums[itemIndex - Number(data.showCreate)]!;
                return (
                    <AlbumTile
                        key={album.id}
                        album={album}
                        onSelectAlbum={data.onSelectAlbum}
                        isScrolling={isScrolling}
                        isLinks={data.isLinks}
                    />
                );
            })}
        </div>
    );
};
