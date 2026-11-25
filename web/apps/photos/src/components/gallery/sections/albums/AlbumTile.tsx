import Avatar from "@/components/Avatar";
import { avatarBackgroundColor, avatarTextColor } from "@/services/avatar";
import { Link05Icon, PinIcon, StarIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Stack, Typography, styled } from "@mui/material";
import type { Collection } from "ente-media/collection";
import { ItemCard } from "ente-new/photos/components/Tiles";
import { UnstyledButton } from "ente-new/photos/components/UnstyledButton";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { t } from "i18next";

interface AlbumTileProps {
    album: CollectionSummary;
    collection?: Collection;
    onSelectAlbum: (id: number) => void;
    isScrolling?: boolean;
    isLinks?: boolean;
    countLabel?: string;
    showBadges?: boolean;
}

export const AlbumTile = ({
    album,
    collection,
    onSelectAlbum,
    isScrolling,
    isLinks,
    countLabel,
    showBadges = true,
}: AlbumTileProps) => {
    const showCoverBadges = showBadges && !isLinks;
    const isIncoming = album.attributes.has("sharedIncoming");
    const isPinned =
        album.attributes.has("pinned") || album.attributes.has("shareePinned");
    const isFavorites = album.type == "userFavorites";
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
                {showCoverBadges &&
                    collection &&
                    (isIncoming ? (
                        <CornerBadge sx={bottomRight}>
                            <BadgeAvatar email={collection.owner.email} />
                        </CornerBadge>
                    ) : (
                        <OutgoingShareBadge collection={collection} />
                    ))}
                {showCoverBadges && (isFavorites || isPinned) && (
                    <CornerBadge
                        sx={{
                            ...bottomLeft,
                            gap: "4px",
                            color: "white",
                            opacity: 0.6,
                        }}
                    >
                        {isFavorites && (
                            <HugeiconsIcon
                                icon={StarIcon}
                                size={20}
                                fill="currentColor"
                                aria-hidden
                            />
                        )}
                        {isPinned && (
                            <HugeiconsIcon
                                icon={PinIcon}
                                size={14}
                                aria-hidden
                            />
                        )}
                    </CornerBadge>
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
                    {showBadges && isLinks && isPinned && (
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

const badgeInset = 10;
const badgeAvatarSize = 18;
const badgeAvatarOverlap = 14;
const badgeAvatarLimit = 2;

const topLeft = { top: badgeInset, left: badgeInset };
const bottomLeft = { bottom: badgeInset, left: badgeInset };
const bottomRight = { bottom: badgeInset, right: badgeInset };

const OutgoingShareBadge = ({ collection }: { collection: Collection }) => {
    const { sharees, publicURLs } = collection;
    const publicURL = publicURLs[0];
    if (!sharees.length && !publicURL) return null;
    const isGroup = sharees.length > 1;
    const hasMore = sharees.length > badgeAvatarLimit;
    const shown = sharees.slice(0, badgeAvatarLimit - Number(hasMore));
    const isLinkExpired =
        !!publicURL &&
        publicURL.validTill > 0 &&
        publicURL.validTill < Date.now() * 1000;
    return (
        <CornerBadge
            sx={{
                ...topLeft,
                gap: isGroup ? 0 : "4px",
                ...(isGroup && {
                    padding: "1px",
                    borderRadius: "40px",
                    backgroundColor: "rgba(255,255,255,.92)",
                }),
            }}
        >
            {!!sharees.length && (
                <AvatarStack>
                    {shown.map((sharee) => (
                        <BadgeAvatar key={sharee.id} email={sharee.email} />
                    ))}
                    {hasMore && (
                        <MoreCount
                            style={{
                                backgroundColor: avatarBackgroundColor(
                                    sharees[shown.length]!.id,
                                ),
                            }}
                        >
                            +{sharees.length - shown.length}
                        </MoreCount>
                    )}
                </AvatarStack>
            )}
            {publicURL && (
                <BadgeSlot
                    sx={{
                        color: isLinkExpired
                            ? "warning.main"
                            : isGroup
                              ? "#000"
                              : "white",
                    }}
                >
                    <HugeiconsIcon icon={Link05Icon} size={16} aria-hidden />
                </BadgeSlot>
            )}
        </CornerBadge>
    );
};

const BadgeAvatar = ({ email }: { email: string | undefined }) => (
    <Avatar email={email} size={badgeAvatarSize} opacity={100} />
);

const CornerBadge = styled("span")({
    position: "absolute",
    display: "flex",
    alignItems: "center",
});

const AvatarStack = styled("span")({
    display: "flex",
    "& > * + *": { marginLeft: badgeAvatarOverlap - badgeAvatarSize },
});

const BadgeSlot = styled("span")({
    width: badgeAvatarSize,
    height: badgeAvatarSize,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
});

const MoreCount = styled(BadgeSlot)({
    borderRadius: "50%",
    color: avatarTextColor,
    fontSize: Math.floor(badgeAvatarSize / 2),
    fontWeight: "bold",
});

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
