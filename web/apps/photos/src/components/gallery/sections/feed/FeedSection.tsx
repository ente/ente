import type { FeedItem } from "@/services/feed";
import { downloadAndSaveFiles } from "@/services/save";
import { ReloadIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Alert,
    Box,
    Button,
    CircularProgress,
    IconButton,
    Stack,
    Tooltip,
    Typography,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { v2SubmitButtonSx } from "ente-base/components/SingleInput.styles";
import { FileViewer } from "ente-gallery/components/viewer/FileViewer";
import type { EnteFile } from "ente-media/file";
import { fileFileName } from "ente-media/file-metadata";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import { useEffect, useRef, useState } from "react";
import { GallerySectionLayout } from "../../navigation/GallerySectionLayout";
import { usePhotosNavigation } from "../../navigation/PhotosNavigationContext";
import type { GallerySectionProps } from "../types";
import { FeedItemRow } from "./FeedItemRow";
import { useFeed } from "./use-feed";

interface ViewerTarget {
    item: FeedItem;
    files: EnteFile[];
    initialIndex: number;
    comments: boolean;
}

export const FeedSection = ({
    library,
    operations,
    presentation,
}: GallerySectionProps) => {
    const feed = useFeed(library, operations.onRemotePull);
    const actions = usePhotosNavigation();
    const { setIsFileViewerOpen } = usePhotosAppContext();
    const [viewer, setViewer] = useState<ViewerTarget>();
    const scrollRef = useRef<HTMLDivElement>(null);
    const moreRef = useRef<HTMLDivElement>(null);
    const { hasMore, loadMore, refresh } = feed;
    useEffect(() => {
        const target = moreRef.current;
        if (!target || !hasMore) return;
        const observer = new IntersectionObserver(
            ([entry]) => {
                if (entry?.isIntersecting) loadMore();
            },
            { root: scrollRef.current, rootMargin: "200px" },
        );
        observer.observe(target);
        return () => observer.disconnect();
    }, [hasMore, loadMore, feed.items.length]);
    useEffect(() => () => setIsFileViewerOpen?.(false), [setIsFileViewerOpen]);

    const openAlbum = (item: FeedItem) =>
        actions.selectCollection(item.collectionID);
    const openItem = (item: FeedItem, fileID?: number) => {
        if (item.type === "sharedCollection" && fileID === undefined) {
            openAlbum(item);
            return;
        }
        if (!item.files.length) return;
        setViewer({
            item,
            files: item.files,
            initialIndex: Math.max(
                0,
                item.files.findIndex((file) => file.id === fileID),
            ),
            comments: ["comment", "reply", "commentLike", "replyLike"].includes(
                item.type,
            ),
        });
        setIsFileViewerOpen?.(true);
    };
    const closeViewer = () => {
        setViewer(undefined);
        setIsFileViewerOpen?.(false);
        feed.refreshSocial();
    };

    return (
        <GallerySectionLayout presentation={presentation} fullBleed>
            <Box
                ref={scrollRef}
                sx={{
                    flex: 1,
                    minHeight: 0,
                    display: "flex",
                    flexDirection: "column",
                    overflowY: "auto",
                    px: { xs: 2, sm: 4.5 },
                    py: { xs: 2, md: 4.5 },
                }}
            >
                <Stack
                    sx={{
                        flex: "1 0 auto",
                        width: "100%",
                        maxWidth: 600,
                        mx: "auto",
                        gap: 3,
                    }}
                >
                    <Stack
                        direction="row"
                        sx={{
                            alignItems: "center",
                            justifyContent: "space-between",
                            height: 54,
                            flexShrink: 0,
                        }}
                    >
                        <Typography
                            component="h1"
                            sx={{
                                fontFamily: '"Outfit Variable", sans-serif',
                                fontSize: 24,
                                lineHeight: "32px",
                                fontWeight: 600,
                            }}
                        >
                            {t("feed")}
                        </Typography>
                        <Tooltip title={t("refresh")}>
                            <span>
                                <IconButton
                                    aria-label={t("refresh")}
                                    onClick={refresh}
                                    disabled={feed.refreshing}
                                    size="small"
                                >
                                    {feed.refreshing ? (
                                        <CircularProgress
                                            size={18}
                                            color="inherit"
                                        />
                                    ) : (
                                        <HugeiconsIcon
                                            icon={ReloadIcon}
                                            size={18}
                                            strokeWidth={1.8}
                                        />
                                    )}
                                </IconButton>
                            </span>
                        </Tooltip>
                    </Stack>
                    {feed.failed && (
                        <Alert
                            severity="warning"
                            action={
                                <Button
                                    color="inherit"
                                    size="small"
                                    onClick={refresh}
                                >
                                    {t("retry")}
                                </Button>
                            }
                        >
                            {t("feed_refresh_failed")}
                        </Alert>
                    )}
                    {feed.items.length === 0 ? (
                        feed.refreshing ? (
                            <Stack
                                role="status"
                                sx={{ alignItems: "center", py: 8, gap: 2 }}
                            >
                                <CircularProgress size={24} />
                                <Typography color="text.muted">
                                    {t("loading")}
                                </Typography>
                            </Stack>
                        ) : (
                            <Stack
                                sx={{
                                    flex: 1,
                                    alignItems: "center",
                                    justifyContent: "center",
                                    textAlign: "center",
                                    px: 2,
                                    py: { xs: 6, sm: 8 },
                                    gap: 3,
                                }}
                            >
                                <Box
                                    component="img"
                                    src="/images/feed/empty.png"
                                    alt=""
                                    draggable={false}
                                    sx={{
                                        width: 240,
                                        height: "auto",
                                        maxWidth: "100%",
                                    }}
                                />
                                <Stack
                                    sx={{
                                        alignItems: "center",
                                        gap: 1.5,
                                        maxWidth: 340,
                                    }}
                                >
                                    <Typography
                                        component="h2"
                                        variant="h3"
                                        sx={{
                                            fontFamily:
                                                '"Outfit Variable", sans-serif',
                                            fontSize: { xs: 28, sm: 32 },
                                            lineHeight: 1.25,
                                            color: "text.base",
                                        }}
                                    >
                                        {t("feed_empty_title")}
                                    </Typography>
                                    <Typography
                                        sx={{
                                            color: "text.muted",
                                            lineHeight: 1.5,
                                        }}
                                    >
                                        {t("feed_empty_description")}
                                    </Typography>
                                </Stack>
                                <FocusVisibleButton
                                    color="accent"
                                    sx={[
                                        v2SubmitButtonSx,
                                        {
                                            flex: "none",
                                            width: 240,
                                            maxWidth: "100%",
                                        },
                                    ]}
                                    onClick={() =>
                                        actions.showAlbumOverview("ente")
                                    }
                                >
                                    {t("share_album")}
                                </FocusVisibleButton>
                            </Stack>
                        )
                    ) : (
                        <Stack
                            component="ul"
                            aria-label={t("feed")}
                            sx={{ m: 0, p: 0, gap: "24px" }}
                        >
                            {feed.items.map((item) => (
                                <FeedItemRow
                                    key={item.id}
                                    item={item}
                                    emailByUserID={library.emailByUserID}
                                    anonNames={
                                        feed.socialByCollection[
                                            item.collectionID
                                        ]?.anonNames ?? {}
                                    }
                                    onOpen={openItem}
                                    onOpenAlbum={openAlbum}
                                />
                            ))}
                        </Stack>
                    )}
                    {feed.hasMore && (
                        <Box ref={moreRef} sx={{ textAlign: "center", py: 2 }}>
                            <Button onClick={loadMore}>{t("load_more")}</Button>
                        </Box>
                    )}
                </Stack>
            </Box>
            {viewer && (
                <FileViewer
                    open
                    onClose={closeViewer}
                    files={viewer.files}
                    initialIndex={viewer.initialIndex}
                    user={library.user}
                    activeCollectionID={viewer.item.collectionID}
                    initialSidebar={viewer.comments ? "comments" : undefined}
                    highlightCommentID={
                        viewer.comments ? viewer.item.commentID : undefined
                    }
                    enableComment
                    isCommentsFeatureEnabled
                    hasSocialActivity={
                        viewer.item.type !== "sharedCollection" &&
                        viewer.item.type !== "sharedPhoto"
                    }
                    isInIncomingSharedCollection={
                        library.collections.find(
                            (c) => c.id === viewer.item.collectionID,
                        )?.owner.id !== library.user!.id
                    }
                    collectionSummaries={library.normalCollectionSummaries}
                    collectionNameByID={library.collectionNameByID}
                    fileNormalCollectionIDs={library.fileNormalCollectionIDs}
                    fileCollectionIDs={library.fileNormalCollectionIDs}
                    hiddenCollectionIDs={library.hiddenCollectionIDs}
                    favoriteFileIDs={library.favoriteFileIDs}
                    pendingFavoriteUpdates={library.pendingFavoriteUpdates}
                    onToggleFavorite={operations.onToggleFavorite}
                    onTriggerRemotePull={() =>
                        void operations.onRemotePull({
                            source: "feed-viewer-action",
                        })
                    }
                    onDownload={(file) =>
                        downloadAndSaveFiles(
                            [file],
                            fileFileName(file),
                            operations.onAddSaveGroup,
                        )
                    }
                    onSendLink={operations.onSendLink}
                    onAddFileToCollection={operations.onAddFileToCollection}
                    onRemoteFilesPull={operations.onRemoteFilesPull}
                    onVisualFeedback={operations.onVisualFeedback}
                    onSelectCollection={actions.selectCollectionFromViewer}
                    onSelectPerson={actions.selectPerson}
                />
            )}
        </GallerySectionLayout>
    );
};
