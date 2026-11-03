import { feedActorKey, type FeedActor, type FeedItem } from "@/services/feed";
import {
    Avatar,
    Box,
    ButtonBase,
    Stack,
    styled,
    Typography,
} from "@mui/material";
import { useResolvedContactAvatar } from "ente-contacts";
import { getAvatarColor } from "ente-gallery/utils/avatar-colors";
import type { EnteFile } from "ente-media/file";
import { BaseTileButton, ItemCard } from "ente-new/photos/components/Tiles";
import { t } from "i18next";
import { Trans } from "react-i18next";
import { FeedActivityIcon } from "./FeedIcons";

interface Props {
    item: FeedItem;
    emailByUserID: Map<number, string>;
    anonNames: Record<string, string>;
    onOpen: (item: FeedItem, fileID?: number) => void;
    onOpenAlbum: (item: FeedItem) => void;
}

const useActor = (
    actor: FeedActor,
    emails: Map<number, string>,
    anonNames: Record<string, string>,
) => {
    const anonymous = !!actor.anonUserID || actor.userID <= 0;
    const resolved = useResolvedContactAvatar(
        anonymous
            ? {}
            : { userID: actor.userID, email: emails.get(actor.userID) },
    );
    const name = anonymous
        ? (actor.anonUserID && anonNames[actor.anonUserID]) || t("anonymous")
        : resolved.primaryLabel || t("someone");
    return { name, avatarURL: anonymous ? undefined : resolved.avatarURL };
};

export const FeedItemRow = ({
    item,
    emailByUserID,
    anonNames,
    onOpen,
    onOpenAlbum,
}: Props) => {
    const primary = useActor(item.actors[0]!, emailByUserID, anonNames);
    const shared =
        item.type === "sharedPhoto" || item.type === "sharedCollection";
    const others = item.actors.length - 1;
    const action = feedActionKey(item);
    return (
        <Stack
            component="li"
            data-feed-type={item.type}
            sx={{ listStyle: "none", gap: "12px" }}
        >
            <Stack
                direction="row"
                sx={{ alignItems: "flex-start", gap: "12px", minHeight: 73 }}
            >
                <ButtonBase
                    onClick={() => (shared ? onOpenAlbum(item) : onOpen(item))}
                    sx={{
                        flex: 1,
                        minWidth: 0,
                        display: "block",
                        textAlign: "start",
                        borderRadius: 1,
                        "&.Mui-focusVisible": {
                            outline: "2px solid",
                            outlineColor: "accent.main",
                            outlineOffset: 4,
                        },
                    }}
                >
                    <Stack
                        direction="row"
                        sx={{ alignItems: "center", gap: "10px", mb: "4px" }}
                    >
                        <FeedActivityIcon type={item.type} />
                        <Stack direction="row">
                            {item.actors.slice(0, 2).map((actor, index) => (
                                <FeedActorAvatar
                                    key={feedActorKey(actor)}
                                    {...{
                                        actor,
                                        emailByUserID,
                                        anonNames,
                                        index,
                                    }}
                                />
                            ))}
                        </Stack>
                    </Stack>
                    <Stack sx={{ pl: "42px", gap: "4px" }}>
                        <Stack
                            direction="row"
                            sx={{
                                alignItems: "baseline",
                                gap: "4px",
                                minWidth: 0,
                            }}
                        >
                            <Typography
                                component="span"
                                noWrap
                                sx={{
                                    fontSize: 14,
                                    lineHeight: "18px",
                                    fontWeight: 600,
                                }}
                            >
                                {primary.name}
                            </Typography>
                            {others > 0 && (
                                <Typography
                                    component="span"
                                    sx={{
                                        flexShrink: 0,
                                        fontSize: 14,
                                        lineHeight: "18px",
                                        color: "text.muted",
                                    }}
                                >
                                    {t("feed_and_others", { count: others })}
                                </Typography>
                            )}
                        </Stack>
                        <Typography
                            component="span"
                            sx={{
                                fontSize: 12,
                                fontWeight: 500,
                                lineHeight: "18px",
                                color: "text.muted",
                                overflowWrap: "anywhere",
                            }}
                        >
                            <Trans
                                i18nKey={action}
                                values={{
                                    album: item.collectionName,
                                    count: item.files.length,
                                }}
                                count={item.files.length}
                                components={{ strong: <strong /> }}
                            />
                        </Typography>
                    </Stack>
                </ButtonBase>
                {!shared && item.files[0] && (
                    <Box sx={{ width: 66, height: 66, flexShrink: 0 }}>
                        <FeedThumbnail
                            file={item.files[0]}
                            onClick={() => onOpen(item)}
                        />
                    </Box>
                )}
            </Stack>
            {shared && item.files.length > 0 && (
                <Box
                    sx={{ ml: "42px", width: "min(300px, calc(100% - 42px))" }}
                >
                    <SharedPhotosGrid
                        item={item}
                        onOpen={onOpen}
                        onOpenAlbum={onOpenAlbum}
                    />
                </Box>
            )}
        </Stack>
    );
};

const FeedActorAvatar = ({
    actor,
    emailByUserID,
    anonNames,
    index,
}: {
    actor: FeedActor;
    emailByUserID: Map<number, string>;
    anonNames: Record<string, string>;
    index: number;
}) => {
    const { name, avatarURL } = useActor(actor, emailByUserID, anonNames);
    return (
        <Avatar
            alt=""
            src={avatarURL}
            sx={{
                width: 28,
                height: 28,
                fontSize: 12,
                bgcolor: getAvatarColor(name),
                color: "#fff",
                border: "1.167px solid",
                borderColor: "background.default",
                ml: index ? "-7px" : 0,
                zIndex: 2 - index,
            }}
        >
            {name[0]?.toLocaleUpperCase()}
        </Avatar>
    );
};

const ThumbnailTile = styled(BaseTileButton)({
    width: "100%",
    height: "100%",
    borderRadius: 8,
});
const FeedThumbnail = ({
    file,
    onClick,
}: {
    file: EnteFile;
    onClick: () => void;
}) => (
    <ItemCard coverFile={file} TileComponent={ThumbnailTile} onClick={onClick}>
        <Box
            component="span"
            sx={{
                position: "absolute",
                width: 1,
                height: 1,
                overflow: "hidden",
                clipPath: "inset(50%)",
            }}
        >
            {t("feed_open_file", { title: file.metadata.title })}
        </Box>
    </ItemCard>
);

const SharedPhotosGrid = ({
    item,
    onOpen,
    onOpenAlbum,
}: Pick<Props, "item" | "onOpen" | "onOpenAlbum">) => {
    const files = item.files.slice(0, 4);
    return (
        <Box
            sx={{
                display: "grid",
                gridTemplateColumns: files.length < 3 ? "1fr" : "1fr 1fr",
                gridTemplateRows: files.length === 1 ? "1fr" : "1fr 1fr",
                gap: "2px",
                aspectRatio: "1",
                borderRadius: "12px",
                overflow: "hidden",
            }}
        >
            {files.map((file, index) => (
                <Box
                    key={file.id}
                    sx={{
                        position: "relative",
                        minHeight: 0,
                        gridColumn:
                            files.length === 3 && index === 2
                                ? "1 / -1"
                                : undefined,
                        "& > button": { borderRadius: 0 },
                    }}
                >
                    <FeedThumbnail
                        file={file}
                        onClick={() => onOpen(item, file.id)}
                    />
                    {index === 3 && item.files.length > 4 && (
                        <ButtonBase
                            onClick={() => onOpenAlbum(item)}
                            aria-label={t("feed_open_album", {
                                album: item.collectionName,
                            })}
                            sx={{
                                position: "absolute",
                                right: 6,
                                bottom: 6,
                                px: 1,
                                py: "4px",
                                borderRadius: 10,
                                color: "#fff",
                                bgcolor: "rgba(0,0,0,0.6)",
                                fontSize: 13,
                                fontWeight: 600,
                            }}
                        >
                            +{item.files.length - 4}
                        </ButtonBase>
                    )}
                </Box>
            ))}
        </Box>
    );
};

const feedActionKey = (item: FeedItem) => {
    const own = item.isOwnedByCurrentUser ? "your" : "a";
    const media = item.isVideo ? "video" : "photo";
    const prefix = item.isOwnedByCurrentUser ? "feed_" : "";
    switch (item.type) {
        case "photoLike":
            return `${prefix}liked_${own}_${media}`;
        case "comment":
            return `${prefix}commented_on_${own}_${media}`;
        case "reply":
            return `${prefix}replied_to_${own}_comment`;
        case "commentLike":
            return `${prefix}liked_${own}_comment`;
        case "replyLike":
            return `feed_liked_${own}_reply`;
        case "sharedPhoto":
            return "feed_added_memories";
        case "sharedCollection":
            return "feed_shared_album";
    }
};
