import { ArrowDown01Icon, Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Button, styled } from "@mui/material";
import { ContextMenu, ContextMenuItem } from "ente-base/components/ContextMenu";
import { t } from "i18next";
import { useId, useState } from "react";

interface ActivityAlbum {
    id: number;
    name: string;
}

interface ActivityAlbumMenuProps<T extends ActivityAlbum> {
    albums: T[];
    selected: T | undefined;
    thumbnailURLs: ReadonlyMap<number, string>;
    getCount: (album: T) => number;
    onSelect: (id: number) => void;
}

export function ActivityAlbumMenu<T extends ActivityAlbum>({
    albums,
    selected,
    thumbnailURLs,
    getCount,
    onSelect,
}: ActivityAlbumMenuProps<T>) {
    const triggerId = useId();
    const menuId = useId();
    const [anchorEl, setAnchorEl] = useState<HTMLButtonElement | null>(null);
    const open = Boolean(anchorEl);

    const cover = (album: T | undefined) => (
        <AlbumCover
            src={album && thumbnailURLs.get(album.id)}
            count={album ? getCount(album) : 0}
        />
    );

    return (
        <>
            <Button
                id={triggerId}
                aria-haspopup="menu"
                aria-expanded={open}
                aria-controls={open ? menuId : undefined}
                onClick={(event) => setAnchorEl(event.currentTarget)}
                sx={{
                    gap: 1.5,
                    maxWidth: "100%",
                    px: 1,
                    py: 0.5,
                    borderRadius: "12px",
                    color: "text.base",
                    backgroundColor: "fill.faint",
                    "&:hover": { backgroundColor: "fill.faintHover" },
                }}
            >
                {cover(selected)}
                <Box
                    component="span"
                    sx={{
                        overflow: "hidden",
                        textOverflow: "ellipsis",
                        whiteSpace: "nowrap",
                    }}
                >
                    {selected?.name ?? t("album")}
                </Box>
                <HugeiconsIcon icon={ArrowDown01Icon} size={16} />
            </Button>
            <ContextMenu
                anchorEl={anchorEl}
                open={open}
                onClose={() => setAnchorEl(null)}
                slotProps={{
                    list: { id: menuId, "aria-labelledby": triggerId },
                }}
            >
                {albums.map((album) => {
                    const isSelected = album.id === selected?.id;
                    return (
                        <ContextMenuItem
                            key={album.id}
                            selected={isSelected}
                            role="menuitemradio"
                            aria-checked={isSelected}
                            sx={{
                                whiteSpace: "normal",
                                overflowWrap: "anywhere",
                            }}
                            onClick={() => {
                                setAnchorEl(null);
                                onSelect(album.id);
                            }}
                        >
                            {cover(album)}
                            {album.name}
                            {isSelected && (
                                <HugeiconsIcon
                                    icon={Tick02Icon}
                                    size={18}
                                    style={{ marginInlineStart: "auto" }}
                                />
                            )}
                        </ContextMenuItem>
                    );
                })}
            </ContextMenu>
        </>
    );
}

const AlbumCover = ({ src, count }: { src?: string; count: number }) => (
    <Box sx={{ position: "relative", flexShrink: 0 }}>
        {src ? (
            <AlbumThumbnail src={src} alt="" />
        ) : (
            <Box
                sx={{
                    width: 24,
                    height: 24,
                    borderRadius: "5px",
                    backgroundColor: "#08C225",
                }}
            />
        )}
        <ActivityCount>{count}</ActivityCount>
    </Box>
);

const AlbumThumbnail = styled("img")({
    display: "block",
    width: 24,
    height: 24,
    borderRadius: 5,
    objectFit: "cover",
});

const ActivityCount = styled("span")(({ theme }) => ({
    position: "absolute",
    bottom: 0,
    insetInlineEnd: -4,
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    minWidth: 16,
    minHeight: 16,
    paddingInline: 2,
    borderRadius: 8,
    backgroundColor: theme.vars.palette.background.elevatedPaper,
    color: theme.vars.palette.text.base,
    fontSize: 10,
    fontWeight: 600,
    lineHeight: 1,
}));
