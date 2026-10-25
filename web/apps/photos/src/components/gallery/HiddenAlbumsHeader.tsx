import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import {
    Box,
    IconButton,
    Stack,
    Tooltip,
    Typography,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import { useEffect, useRef } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import { FixedSizeList, type ListChildComponentProps } from "react-window";
import { AlbumCard } from "./AlbumsOverview";

interface HiddenAlbumsHeaderProps {
    albums: CollectionSummary[];
    onSelectAlbum: (id: number) => void;
    onBackToAlbums: () => void;
}

export const HiddenAlbumsHeader = ({
    albums,
    onSelectAlbum,
    onBackToAlbums,
}: HiddenAlbumsHeaderProps) => {
    const compact = useMediaQuery(useTheme().breakpoints.down("md"));
    const listRef = useRef<FixedSizeList>(null);
    const tileWidth = compact ? 104 : 140;
    const gap = compact ? 12 : 22;

    useEffect(() => {
        listRef.current?.scrollTo(0);
    }, [albums]);

    return (
        <Stack sx={{ width: "100%", minWidth: 0, gap: "24px", pb: "16px" }}>
            <Stack direction="row" sx={{ alignItems: "center", gap: 1 }}>
                <Tooltip title={t("go_back")}>
                    <IconButton
                        aria-label={t("go_back")}
                        onClick={onBackToAlbums}
                        sx={{ width: 32, height: 32 }}
                    >
                        <ArrowBackIcon sx={{ fontSize: 20 }} />
                    </IconButton>
                </Tooltip>
                <Typography
                    component="h1"
                    sx={{
                        fontFamily: '"Outfit Variable", Outfit, sans-serif',
                        fontSize: { xs: 20, md: 24 },
                        lineHeight: "32px",
                        fontWeight: 600,
                    }}
                >
                    {t("section_hidden")}
                </Typography>
            </Stack>
            {!!albums.length && (
                <Box
                    role="region"
                    aria-label={t("hidden_albums")}
                    sx={{
                        position: "relative",
                        height: tileWidth + 62,
                        "--album-tile-width": `${tileWidth}px`,
                        "--album-name-size": compact ? "13px" : "14px",
                        "--album-count-size": compact ? "11px" : "12px",
                        "&::after": {
                            content: '""',
                            position: "absolute",
                            insetBlock: 0,
                            insetInlineEnd: 0,
                            width: "32px",
                            background:
                                "linear-gradient(to right, transparent, var(--mui-palette-background-default))",
                            pointerEvents: "none",
                        },
                    }}
                >
                    <AutoSizer>
                        {({ width, height }) => (
                            <FixedSizeList
                                ref={listRef}
                                layout="horizontal"
                                width={width}
                                height={height}
                                itemCount={albums.length}
                                itemSize={tileWidth + gap}
                                itemKey={(index, data) =>
                                    data.albums[index]!.id
                                }
                                itemData={{ albums, onSelectAlbum }}
                                useIsScrolling
                                style={{ overflowY: "hidden" }}
                            >
                                {AlbumStripItem}
                            </FixedSizeList>
                        )}
                    </AutoSizer>
                </Box>
            )}
        </Stack>
    );
};

const AlbumStripItem = ({
    data,
    index,
    style,
    isScrolling,
}: ListChildComponentProps<
    Pick<HiddenAlbumsHeaderProps, "albums" | "onSelectAlbum">
>) => (
    <div style={style}>
        <AlbumCard
            album={data.albums[index]!}
            onSelectAlbum={data.onSelectAlbum}
            isScrolling={isScrolling}
        />
    </div>
);
