import { SectionBackButton } from "@/components/gallery/SectionBackButton";
import { sectionHeadingHeight } from "@/components/gallery/header-styles";
import { ArrowLeft01Icon, ArrowRight01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, IconButton, Stack } from "@mui/material";
import { GalleryItemsSummary } from "ente-new/photos/components/gallery/ListHeader";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import { useRef, useState } from "react";
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
    const [scrollOffset, setScrollOffset] = useState(0);
    const listOuterRef = useRef<HTMLDivElement>(null);
    const scrollByPage = (direction: 1 | -1, width: number) =>
        listOuterRef.current?.scrollBy({
            left:
                direction *
                Math.max(tileWidth, Math.floor(width / tileWidth) * tileWidth),
            behavior: "smooth",
        });

    return (
        <Stack sx={{ height, gap: "24px" }}>
            <Stack
                direction="row"
                sx={{
                    alignItems: "center",
                    minHeight: sectionHeadingHeight,
                    gap: 1,
                }}
            >
                <SectionBackButton />
                <GalleryItemsSummary
                    name={title}
                    fileCount={fileCount}
                    nameProps={{ component: "h2" }}
                />
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
                        {({ width }) => {
                            const canScrollLeft = scrollOffset > 1;
                            const canScrollRight =
                                albums.length * tileWidth -
                                    width -
                                    scrollOffset >
                                1;
                            return (
                                <Box sx={{ position: "relative", width }}>
                                    <FixedSizeList
                                        outerRef={listOuterRef}
                                        layout="horizontal"
                                        width={width}
                                        height={200}
                                        itemCount={albums.length}
                                        itemSize={tileWidth}
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
                                            maskImage: canScrollRight
                                                ? "linear-gradient(to right, black calc(100% - 110px), transparent 100%)"
                                                : undefined,
                                        }}
                                    >
                                        {HeaderAlbumTile}
                                    </FixedSizeList>
                                    {canScrollLeft && (
                                        <StripScrollButton
                                            side="left"
                                            onClick={() =>
                                                scrollByPage(-1, width)
                                            }
                                        />
                                    )}
                                    {canScrollRight && (
                                        <StripScrollButton
                                            side="right"
                                            onClick={() =>
                                                scrollByPage(1, width)
                                            }
                                        />
                                    )}
                                </Box>
                            );
                        }}
                    </AutoSizer>
                </Box>
            )}
        </Stack>
    );
};

const tileWidth = 162;

const StripScrollButton = ({
    side,
    onClick,
}: {
    side: "left" | "right";
    onClick: () => void;
}) => (
    // Matches the photo viewer's previous and next arrows.
    <IconButton
        aria-label={t(side == "left" ? "previous" : "next")}
        onClick={onClick}
        sx={{
            position: "absolute",
            top: 48,
            [side]: 12,
            width: 44,
            height: 44,
            borderRadius: "12px",
            bgcolor: "rgb(43 43 43 / 0.3)",
            color: "#fff",
            transition: "transform 0.2s cubic-bezier(0.22, 1, 0.36, 1)",
            "&:hover": { bgcolor: "rgb(55 55 55 / 0.5)" },
            "@media (hover: hover) and (prefers-reduced-motion: no-preference)":
                { "&:hover:not(:active)": { transform: "translateY(-2px)" } },
            "&:active": { transform: "scale(0.985)" },
            "@media (prefers-reduced-motion: reduce)": {
                "&:active": { transform: "none" },
            },
            "&:focus-visible": {
                outline: "1px solid #08c225",
                outlineOffset: "2px",
            },
        }}
    >
        <HugeiconsIcon
            icon={side == "left" ? ArrowLeft01Icon : ArrowRight01Icon}
            size={20}
            strokeWidth={1.8}
        />
    </IconButton>
);

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
