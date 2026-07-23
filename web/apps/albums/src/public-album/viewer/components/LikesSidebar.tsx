import { downloadManager } from "@/public-album/download/services/download-manager";
import { getStoredAnonIdentity } from "@/public-album/social/api/public-reaction";
import { useBrowserBackClose } from "@/shared/hooks/useBrowserBackClose";
import CloseIcon from "@mui/icons-material/Close";
import {
    Avatar,
    Box,
    CircularProgress,
    Drawer,
    IconButton,
    Stack,
    styled,
    Typography,
} from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import log from "ente-base/log";
import { getAvatarColor } from "ente-gallery/utils/avatar-colors";
import type { EnteFile } from "ente-media/file";
import { t } from "i18next";
import React, {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import type { UnifiedReaction } from "../lib/social-types";

// =============================================================================
// Icons
// =============================================================================

const ChevronDownIcon: React.FC = () => (
    <svg
        width="22"
        height="22"
        viewBox="0 0 20 20"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        style={{ marginLeft: -6, transform: "translateY(-2px)" }}
    >
        <path
            d="M10.0007 12.5004L6.46484 8.96544L7.64401 7.78711L10.0007 10.1438L12.3573 7.78711L13.5365 8.96544L10.0007 12.5004Z"
            fill="currentColor"
        />
    </svg>
);

const HeartFilledIcon: React.FC = () => (
    <svg
        width="18"
        height="16"
        viewBox="0 0 30 26"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M12.4926 23.4794C8.64537 20.6025 1.02344 14.0254 1.02344 8.10676C1.02344 4.19475 3.89425 1.02344 7.84162 1.02344C9.88707 1.02344 11.9325 1.70526 14.6598 4.43253C17.3871 1.70526 19.4325 1.02344 21.478 1.02344C25.4253 1.02344 28.2962 4.19475 28.2962 8.10676C28.2962 14.0254 20.6743 20.6025 16.827 23.4794C15.5324 24.4474 13.7872 24.4474 12.4926 23.4794Z"
            fill="#08C225"
            stroke="#08C225"
            strokeWidth="2.04545"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
    </svg>
);

const PersonIcon: React.FC = () => (
    <svg
        width="16"
        height="16"
        viewBox="0 0 24 24"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M12 12C14.21 12 16 10.21 16 8C16 5.79 14.21 4 12 4C9.79 4 8 5.79 8 8C8 10.21 9.79 12 12 12ZM12 14C9.33 14 4 15.34 4 18V20H20V18C20 15.34 14.67 14 12 14Z"
            fill="currentColor"
        />
    </svg>
);

// =============================================================================
// Types
// =============================================================================

/** A liker with display info. */
interface Liker {
    id: string;
    userID: number;
    anonUserID?: string;
    userName: string;
    /** The actual email for avatar color, even when userName is "You". */
    email: string;
    /** The first letter of the actual name (not "You") for the avatar. */
    avatarInitial: string;
    /** True if this is a registered user with masked email (show person icon). */
    isMaskedEmail: boolean;
}

/** Collection info for the dropdown. */
interface CollectionInfo {
    id: number;
    name: string;
    likeCount: number;
    coverFile?: EnteFile;
}

// =============================================================================
// Main Component
// =============================================================================

export interface LikesSidebarProps extends ModalVisibilityProps {
    /**
     * The file whose likes are being displayed.
     */
    file?: EnteFile;
    /**
     * True while the parent is fetching the initial social payload for the
     * current file.
     */
    isSocialDataLoading?: boolean;
    /**
     * The currently active collection ID (when viewing from within a collection).
     */
    activeCollectionID?: number;
    /**
     * The current user's ID.
     */
    currentUserID?: number;
    /**
     * Pre-fetched reactions by collection ID (includes both file and comment reactions).
     */
    prefetchedReactions?: Map<number, UnifiedReaction[]>;
    /**
     * Pre-fetched user ID to email mapping.
     */
    prefetchedUserIDToEmail?: Map<number, string>;
    /**
     * Map of anonymous user ID to decrypted user name.
     */
    anonUserNames?: Map<string, string>;
}

/**
 * A sidebar panel for displaying users who liked a file.
 */
export const LikesSidebar: React.FC<LikesSidebarProps> = ({
    open,
    onClose,
    file,
    isSocialDataLoading = false,
    activeCollectionID,
    currentUserID,
    prefetchedReactions,
    prefetchedUserIDToEmail,
    anonUserNames,
}) => {
    useBrowserBackClose({
        open,
        onClose,
        stateKey: "__enteLikesSidebarBackState",
    });

    const [loading, setLoading] = useState(false);
    const [collectionDropdownOpen, setCollectionDropdownOpen] = useState(false);
    const showLoading = loading || isSocialDataLoading;

    // Reactions grouped by collection: collectionID -> reactions
    const [reactionsByCollection, setReactionsByCollection] = useState<
        Map<number, UnifiedReaction[]>
    >(new Map());

    // Selected collection for viewing likes (when in gallery view)
    const [selectedCollectionID, setSelectedCollectionID] = useState<
        number | undefined
    >(undefined);

    // Thumbnail URLs for each collection's cover file: collectionID -> URL
    const [thumbnailURLs, setThumbnailURLs] = useState<Map<number, string>>(
        new Map(),
    );

    // Check if opened from a collection context
    const hasCollectionContext =
        activeCollectionID !== undefined && activeCollectionID !== 0;

    // Build collection info for the current public album.
    const collectionsInfo = useMemo((): CollectionInfo[] => {
        if (!file) return [];

        return [
            {
                id: file.collectionID,
                name: "Album",
                likeCount:
                    reactionsByCollection
                        .get(file.collectionID)
                        ?.filter((r) => r.reactionType === "green_heart")
                        .length ?? 0,
                coverFile: file,
            },
        ];
    }, [file, reactionsByCollection]);

    // Collections sorted by like count (descending) for dropdown
    const sortedCollectionsInfo = useMemo(() => {
        return [...collectionsInfo].sort((a, b) => b.likeCount - a.likeCount);
    }, [collectionsInfo]);

    // Currently selected collection info
    const selectedCollectionInfo = useMemo(() => {
        const targetID = hasCollectionContext
            ? activeCollectionID
            : selectedCollectionID;
        return (
            collectionsInfo.find((c) => c.id === targetID) ??
            sortedCollectionsInfo[0]
        );
    }, [
        hasCollectionContext,
        activeCollectionID,
        selectedCollectionID,
        collectionsInfo,
        sortedCollectionsInfo,
    ]);

    // Get likers for the selected collection
    const likers = useMemo((): Liker[] => {
        if (!selectedCollectionInfo) return [];
        const reactions =
            reactionsByCollection.get(selectedCollectionInfo.id) ?? [];

        // Get stored anonymous identity for this collection to check if current anon user
        const storedAnonIdentity = getStoredAnonIdentity(
            selectedCollectionInfo.id,
        );

        return reactions
            .filter((r) => r.reactionType === "green_heart")
            .sort((a, b) => b.createdAt - a.createdAt) // Most recent first
            .map((r) => {
                // Check if this is an anonymous user
                const isAnonymous =
                    r.anonUserID || r.userID === 0 || r.userID === -1;

                // Check if this is the current user (logged-in or anonymous)
                const isCurrentUser = r.userID === currentUserID;
                const isCurrentAnonUser =
                    storedAnonIdentity &&
                    r.anonUserID === storedAnonIdentity.anonUserID;

                let email: string;
                let userName: string;
                let actualName: string;

                if (isAnonymous) {
                    // Use decrypted name from anonUserNames if available
                    const decryptedName = r.anonUserID
                        ? anonUserNames?.get(r.anonUserID)
                        : undefined;
                    actualName =
                        decryptedName ??
                        `${t("anonymous")} ${r.anonUserID?.slice(-4) ?? ""}`;
                    // Use actualName for avatar color (varying length like mobile emails)
                    email = actualName;
                    userName = isCurrentAnonUser ? t("you") : actualName;
                } else {
                    const emailFromMap = prefetchedUserIDToEmail?.get(r.userID);
                    // Use userID as string for unique avatar color
                    email = emailFromMap ?? String(r.userID);
                    // In public albums (no currentUserID), non-anonymous
                    // users are album owner or collaborators
                    actualName = emailFromMap ?? t("anonymous");
                    userName = isCurrentUser ? t("you") : actualName;
                }

                // Check if email is masked (starts with *)
                const isMaskedEmail =
                    !isAnonymous && actualName.startsWith("*");

                return {
                    id: r.id,
                    userID: r.userID,
                    anonUserID: r.anonUserID,
                    userName,
                    email,
                    avatarInitial: actualName[0]?.toUpperCase() ?? "?",
                    isMaskedEmail,
                };
            });
    }, [
        selectedCollectionInfo,
        reactionsByCollection,
        currentUserID,
        prefetchedUserIDToEmail,
        anonUserNames,
    ]);

    // Load reactions from prefetched data
    const loadReactions = useCallback(() => {
        if (!file || !open || !prefetchedReactions) return;

        setLoading(true);

        try {
            // Use prefetched reactions (filter to only file reactions, not comment reactions)
            const filteredReactions = new Map<number, UnifiedReaction[]>();
            for (const [collectionID, reactions] of prefetchedReactions) {
                const fileReactions = reactions.filter(
                    (r) => !r.commentID && r.fileID === file.id,
                );
                filteredReactions.set(collectionID, fileReactions);
            }

            setReactionsByCollection(filteredReactions);
        } catch (e) {
            log.error("Failed to load reactions", e);
        } finally {
            setLoading(false);
        }
    }, [file, open, prefetchedReactions]);

    // Track previous open state to detect when sidebar opens
    const prevOpenRef = useRef(false);

    // Load reactions and set initial selection when the sidebar opens
    useEffect(() => {
        if (open && !prevOpenRef.current) {
            // Sidebar just opened - load reactions and set initial selection
            loadReactions();

            // Set initial selection to album with most likes (gallery view only)
            if (
                !hasCollectionContext &&
                prefetchedReactions &&
                prefetchedReactions.size > 0
            ) {
                let maxCount = -1;
                let bestCollectionID: number | undefined;
                for (const [collectionID, reactions] of prefetchedReactions) {
                    const count = reactions.filter(
                        (r) =>
                            !r.commentID &&
                            r.fileID === file?.id &&
                            r.reactionType === "green_heart",
                    ).length;
                    if (count > maxCount) {
                        maxCount = count;
                        bestCollectionID = collectionID;
                    }
                }
                if (bestCollectionID !== undefined) {
                    setSelectedCollectionID(bestCollectionID);
                }
            }
        }
        prevOpenRef.current = open;
    }, [
        open,
        loadReactions,
        hasCollectionContext,
        prefetchedReactions,
        file?.id,
    ]);

    // Update local state when prefetchedReactions changes (e.g., like/unlike from heart button)
    useEffect(() => {
        if (!open || !file || !prefetchedReactions) return;

        // Filter to only file reactions (not comment reactions)
        const filteredReactions = new Map<number, UnifiedReaction[]>();
        for (const [collectionID, reactions] of prefetchedReactions) {
            const fileReactions = reactions.filter(
                (r) => !r.commentID && r.fileID === file.id,
            );
            filteredReactions.set(collectionID, fileReactions);
        }

        setReactionsByCollection(filteredReactions);
    }, [open, file, prefetchedReactions]);

    // Fetch thumbnails for each collection's cover file
    useEffect(() => {
        // Only fetch when open, don't clear when closing (avoids flash during animation)
        if (!open || collectionsInfo.length === 0) {
            return;
        }

        let didCancel = false;

        const fetchThumbnails = async () => {
            const urls = new Map<number, string>();
            for (const collection of collectionsInfo) {
                if (collection.coverFile) {
                    try {
                        const url =
                            await downloadManager.renderableThumbnailURL(
                                collection.coverFile,
                            );
                        if (!didCancel && url) {
                            urls.set(collection.id, url);
                        }
                    } catch (e) {
                        log.warn(
                            `Failed to fetch thumbnail for collection ${collection.id}`,
                            e,
                        );
                    }
                }
            }
            if (!didCancel) {
                setThumbnailURLs(urls);
            }
        };

        void fetchThumbnails();

        return () => {
            didCancel = true;
        };
    }, [open, collectionsInfo]);

    const handleCollectionSelect = (collectionID: number) => {
        setSelectedCollectionID(collectionID);
        setCollectionDropdownOpen(false);
    };

    const showOverlay = collectionDropdownOpen;

    return (
        <SidebarDrawer open={open} onClose={onClose} anchor="right">
            <DrawerContentWrapper>
                {showOverlay && (
                    <ContextMenuOverlay
                        onClick={() => {
                            setCollectionDropdownOpen(false);
                        }}
                    />
                )}
                <Header>
                    {hasCollectionContext ? (
                        <Typography
                            sx={(theme) => ({
                                color: "#000",
                                fontWeight: 600,
                                ...theme.applyStyles("dark", { color: "#fff" }),
                            })}
                        >
                            {showLoading
                                ? t("loading")
                                : t("like_count", { count: likers.length })}
                        </Typography>
                    ) : collectionsInfo.length > 1 ? (
                        <Box
                            sx={{
                                position: "relative",
                                zIndex: collectionDropdownOpen ? 12 : "auto",
                            }}
                        >
                            <CollectionDropdownButton
                                onClick={() =>
                                    setCollectionDropdownOpen(
                                        !collectionDropdownOpen,
                                    )
                                }
                            >
                                <Box sx={{ position: "relative" }}>
                                    {selectedCollectionInfo &&
                                    thumbnailURLs.get(
                                        selectedCollectionInfo.id,
                                    ) ? (
                                        <CollectionThumbnail
                                            src={thumbnailURLs.get(
                                                selectedCollectionInfo.id,
                                            )}
                                            alt=""
                                        />
                                    ) : (
                                        <CollectionThumbnailPlaceholder />
                                    )}
                                    <CollectionBadge>
                                        {selectedCollectionInfo?.likeCount ?? 0}
                                    </CollectionBadge>
                                </Box>
                                <Typography
                                    sx={(theme) => ({
                                        color: "#000",
                                        fontWeight: 600,
                                        fontSize: 14,
                                        lineHeight: "20px",
                                        marginBottom: "4px",
                                        ...theme.applyStyles("dark", {
                                            color: "#fff",
                                        }),
                                    })}
                                >
                                    {selectedCollectionInfo?.name ?? "Album"}
                                </Typography>
                                <ChevronDownIcon />
                            </CollectionDropdownButton>
                            {collectionDropdownOpen && (
                                <CollectionDropdownMenu>
                                    {sortedCollectionsInfo.map((collection) => (
                                        <CollectionDropdownItem
                                            key={collection.id}
                                            onClick={() =>
                                                handleCollectionSelect(
                                                    collection.id,
                                                )
                                            }
                                        >
                                            <Box sx={{ position: "relative" }}>
                                                {thumbnailURLs.get(
                                                    collection.id,
                                                ) ? (
                                                    <CollectionThumbnail
                                                        src={thumbnailURLs.get(
                                                            collection.id,
                                                        )}
                                                        alt=""
                                                    />
                                                ) : (
                                                    <CollectionThumbnailPlaceholder />
                                                )}
                                                <CollectionBadge>
                                                    {collection.likeCount}
                                                </CollectionBadge>
                                            </Box>
                                            <Typography
                                                sx={(theme) => ({
                                                    color: "#000",
                                                    fontWeight: 600,
                                                    fontSize: 14,
                                                    lineHeight: "20px",
                                                    marginBottom: "4px",
                                                    ...theme.applyStyles(
                                                        "dark",
                                                        { color: "#fff" },
                                                    ),
                                                })}
                                            >
                                                {collection.name}
                                            </Typography>
                                        </CollectionDropdownItem>
                                    ))}
                                </CollectionDropdownMenu>
                            )}
                        </Box>
                    ) : (
                        <Typography
                            sx={(theme) => ({
                                color: "#000",
                                fontWeight: 600,
                                ...theme.applyStyles("dark", { color: "#fff" }),
                            })}
                        >
                            {showLoading
                                ? t("loading")
                                : t("like_count", { count: likers.length })}
                        </Typography>
                    )}
                    <CloseButton onClick={onClose}>
                        <CloseIcon sx={{ fontSize: 22 }} />
                    </CloseButton>
                </Header>

                <LikersContainer>
                    {showLoading ? (
                        <LoadingContainer>
                            <CircularProgress size={24} />
                        </LoadingContainer>
                    ) : likers.length === 0 ? (
                        <EmptyMessage>{t("no_likes_yet")}</EmptyMessage>
                    ) : (
                        likers.map((liker) => (
                            <LikerRow key={liker.id}>
                                <Avatar
                                    sx={{
                                        width: 32,
                                        height: 32,
                                        fontSize: 14,
                                        bgcolor: getAvatarColor(liker.email),
                                        color: "#fff",
                                    }}
                                >
                                    {liker.isMaskedEmail ? (
                                        <PersonIcon />
                                    ) : (
                                        liker.avatarInitial
                                    )}
                                </Avatar>
                                <LikerName>{liker.userName}</LikerName>
                                <HeartFilledIcon />
                            </LikerRow>
                        ))
                    )}
                </LikersContainer>
            </DrawerContentWrapper>
        </SidebarDrawer>
    );
};

// =============================================================================
// Styled Components
// =============================================================================

// Drawer & Layout
const SidebarDrawer = styled(Drawer)(({ theme }) => ({
    "& .MuiDrawer-paper": {
        width: "23vw",
        minWidth: "520px",
        maxWidth: "calc(100% - 32px)",
        height: "calc(100% - 32px)",
        margin: "16px",
        borderRadius: "36px",
        backgroundColor: "#fff",
        padding: "24px 24px 32px 24px",
        boxShadow: "none",
        border: "1px solid #E0E0E0",
        display: "flex",
        flexDirection: "column",
        overflow: "visible",
        "@media (max-width: 450px)": {
            width: "100%",
            minWidth: "unset",
            maxWidth: "100%",
            height: "100%",
            margin: 0,
            borderRadius: 0,
        },
        ...theme.applyStyles("dark", {
            backgroundColor: "#1b1b1b",
            border: "1px solid rgba(255, 255, 255, 0.18)",
        }),
    },
    "& .MuiBackdrop-root": { backgroundColor: "transparent" },
}));

const DrawerContentWrapper = styled(Box)(() => ({
    position: "relative",
    display: "flex",
    flexDirection: "column",
    flex: 1,
    minHeight: 0,
}));

const Header = styled(Stack)(() => ({
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginBottom: 48,
}));

const CloseButton = styled(IconButton)(({ theme }) => ({
    backgroundColor: "#F5F5F7",
    color: "#000",
    padding: "8px",
    "&:hover": { backgroundColor: "#E5E5E7" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255, 255, 255, 0.12)",
        color: "#fff",
        "&:hover": { backgroundColor: "rgba(255, 255, 255, 0.16)" },
    }),
}));

// Collection Dropdown
const CollectionDropdownButton = styled(Box)(({ theme }) => ({
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    gap: 14,
    padding: "5px 6px 0px 6px",
    borderRadius: 12,
    backgroundColor: "#F0F0F0",
    cursor: "pointer",
    "&:hover": { backgroundColor: "#E8E8E8" },
    ...theme.applyStyles("dark", {
        backgroundColor: "#363636",
        "&:hover": { backgroundColor: "#404040" },
    }),
}));

const CollectionThumbnail = styled("img")(() => ({
    width: 24,
    height: 24,
    borderRadius: 5,
    objectFit: "cover",
}));

const CollectionThumbnailPlaceholder = styled(Box)(() => ({
    width: 24,
    height: 24,
    borderRadius: 5,
    backgroundColor: "#08C225",
}));

const CollectionBadge = styled(Box)(({ theme }) => ({
    position: "absolute",
    bottom: 4,
    right: -4,
    display: "inline-flex",
    justifyContent: "center",
    alignItems: "center",
    borderRadius: "50%",
    backgroundColor: "#FFF",
    color: "#000",
    fontSize: 10,
    fontWeight: 600,
    lineHeight: 1,
    minWidth: 16,
    minHeight: 16,
    ...theme.applyStyles("dark", { backgroundColor: "#fff", color: "#000" }),
}));

const CollectionDropdownMenu = styled(Box)(({ theme }) => ({
    position: "absolute",
    top: "calc(100% + 8px)",
    left: 0,
    display: "flex",
    flexDirection: "column",
    justifyContent: "center",
    alignItems: "flex-start",
    width: 184,
    padding: 4,
    gap: 4,
    borderRadius: 12,
    border: "1px solid rgba(0, 0, 0, 0.08)",
    backgroundColor: "#F0F0F0",
    zIndex: 12,
    ...theme.applyStyles("dark", {
        border: "1px solid rgba(0, 0, 0, 0.08)",
        backgroundColor: "#363636",
    }),
}));

const CollectionDropdownItem = styled(Box)(({ theme }) => ({
    display: "flex",
    alignItems: "center",
    gap: 14,
    padding: "5px 6px 0px 6px",
    borderRadius: 8,
    cursor: "pointer",
    width: "100%",
    "&:hover": { backgroundColor: "#E8E8E8" },
    ...theme.applyStyles("dark", {
        "&:hover": { backgroundColor: "rgba(255, 255, 255, 0.16)" },
    }),
}));

const LikersContainer = styled(Box)(({ theme }) => ({
    flex: 1,
    overflow: "auto",
    marginRight: -24,
    paddingRight: 24,
    "&::-webkit-scrollbar": { width: "6px" },
    "&::-webkit-scrollbar-track": { background: "transparent" },
    "&::-webkit-scrollbar-thumb": {
        background: "rgba(0, 0, 0, 0.2)",
        borderRadius: "3px",
    },
    scrollbarWidth: "thin",
    scrollbarColor: "rgba(0, 0, 0, 0.2) transparent",
    ...theme.applyStyles("dark", {
        "&::-webkit-scrollbar-thumb": {
            background: "rgba(255, 255, 255, 0.2)",
        },
        scrollbarColor: "rgba(255, 255, 255, 0.2) transparent",
    }),
}));

const LikerRow = styled(Box)(() => ({
    display: "flex",
    alignItems: "center",
    gap: 12,
    padding: "10px 10px 10px 0",
}));

const LikerName = styled(Typography)(({ theme }) => ({
    flex: 1,
    fontWeight: 500,
    color: "#000",
    fontSize: 14,
    ...theme.applyStyles("dark", { color: "#fff" }),
}));

const LoadingContainer = styled(Box)(() => ({
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    height: "100%",
    // Offset for header (marginBottom: 48) + padding diff (32-24=8) = 56, halved
    marginTop: -28,
}));

const EmptyMessage = styled(Typography)(({ theme }) => ({
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    height: "100%",
    // Offset for header (marginBottom: 48) + padding diff (32-24=8) = 56, halved
    marginTop: -28,
    color: "#666",
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.5)" }),
}));

// Context Menu Overlay
const ContextMenuOverlay = styled(Box)(() => ({
    position: "absolute",
    top: -25,
    left: -25,
    right: -25,
    bottom: -33,
    backgroundColor: "rgba(0, 0, 0, 0.6)",
    zIndex: 10,
    borderRadius: "36px",
    "@media (max-width: 450px)": { borderRadius: 0 },
}));
