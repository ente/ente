import { useDeleteEmptyAlbums } from "@/components/Collections/useDeleteEmptyAlbums";
import type { RemotePullOpts } from "@/components/gallery";
import type { AlbumFilter } from "@/utils/album-filters";
import { Delete02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import AddIcon from "@mui/icons-material/Add";
import PushPinIcon from "@mui/icons-material/PushPin";
import {
    Box,
    IconButton,
    Stack,
    Tooltip,
    Typography,
    styled,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import { ItemCard } from "ente-new/photos/components/Tiles";
import { UnstyledButton } from "ente-new/photos/components/UnstyledButton";
import type {
    CollectionSummary,
    CollectionsSortBy,
} from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import { useEffect, useRef, useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import { FixedSizeList, type ListChildComponentProps } from "react-window";

interface AlbumsOverviewProps {
    albums: CollectionSummary[];
    title: string;
    filter: AlbumFilter;
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
                            {t("album_overview_count", {
                                count: albums.length,
                            })}
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
                const album = data.albums[start + offset];
                if (!album)
                    return (
                        <AlbumButton key="create" onClick={data.onCreateAlbum}>
                            <Cover
                                sx={{
                                    border: "1.5px dashed",
                                    borderColor: "stroke.faint",
                                    display: "flex",
                                    alignItems: "center",
                                    justifyContent: "center",
                                    color: "text.muted",
                                }}
                            >
                                <AddIcon />
                            </Cover>
                            <Typography
                                component="span"
                                sx={{
                                    fontSize: "var(--album-name-size)",
                                    lineHeight: "20px",
                                    fontWeight: 500,
                                    color: "text.muted",
                                }}
                            >
                                {t("new_album")}
                            </Typography>
                        </AlbumButton>
                    );
                const badge = album.attributes.has("sharedIncoming")
                    ? t("album_overview_received_title")
                    : album.attributes.has("sharedOutgoing") ||
                        album.attributes.has("sharedViaLink")
                      ? t("shared_albums_label")
                      : undefined;
                return (
                    <AlbumButton
                        key={album.id}
                        title={album.name}
                        onClick={() => data.onSelectAlbum(album.id)}
                    >
                        <ItemCard
                            TileComponent={Cover}
                            coverFile={album.coverFile}
                            isScrolling={isScrolling}
                        >
                            {badge && (
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
                            sx={{ width: "100%", gap: "2px" }}
                        >
                            <Stack
                                component="span"
                                direction="row"
                                sx={{
                                    alignItems: "center",
                                    gap: "4px",
                                    minWidth: 0,
                                }}
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
                                {(album.attributes.has("pinned") ||
                                    album.attributes.has("shareePinned")) && (
                                    <PushPinIcon
                                        sx={{
                                            flexShrink: 0,
                                            fontSize: 12,
                                            color: "text.faint",
                                        }}
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
                                {t("album_items_count", {
                                    count: album.fileCount,
                                })}
                            </Typography>
                        </Stack>
                    </AlbumButton>
                );
            })}
        </div>
    );
};

const AlbumButton = styled(UnstyledButton)(({ theme }) => ({
    width: "var(--album-tile-width)",
    display: "flex",
    flexDirection: "column",
    alignItems: "flex-start",
    gap: 8,
    color: theme.vars.palette.text.base,
    textAlign: "left",
    borderRadius: 12,
    "&:hover": { opacity: 0.86 },
    "&:focus-visible": {
        outline: `2px solid ${theme.vars.palette.stroke.base}`,
        outlineOffset: -2,
    },
}));

const Cover = styled("div")({
    width: "var(--album-tile-width)",
    height: "var(--album-tile-width)",
    flexShrink: 0,
    borderRadius: 12,
    overflow: "hidden",
    position: "relative",
    "& > img": {
        width: "100%",
        height: "100%",
        objectFit: "cover",
        display: "block",
    },
});
