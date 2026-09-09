import { ArrowLeft02Icon, ArrowRight02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { SpaceAddFriendDialog } from "components/AddFriendDialog";
import { SpaceAddFriendTile } from "components/AddFriendTile";
import { SpaceFileViewer } from "components/FileViewer";
import { SpaceHomeHeader, spaceHomeHeaderHeight } from "components/HomeHeader";
import { SpaceOwnPostTile } from "components/OwnPostTile";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React from "react";
import { FriendPostTile } from "screens/HomeScreen";
import type { SetupProfile } from "screens/SetupProfileScreen";
import { spaceInviteURL } from "services/invite";
import type { SpacePost } from "services/space";
import { spaceAppBackground, spaceSurface, spaceText } from "styles/colors";
import {
    spacePostTileRadius,
    spaceTileCircleInset,
    spaceTileCornerStyles,
} from "styles/tiles";
import {
    homeTileGap,
    homeTileLayout,
    maximumHomeTileCount,
    minimumHomeTileCanvasHeight,
    type HomeTilePlacement,
} from "utils/home-tile-layout";
import { spaceDefaultCoverImagePath } from "utils/post-image";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const controlButtonColor = spaceSurface;
const demoProfile: SetupProfile = {
    avatarUrl: null,
    fullName: "Alex Morgan",
    spaceId: "demo-self",
    username: "you",
};
const demoOwnPosts: SpacePost[] = [
    spaceDefaultCoverImagePath,
    "/images/invite-bg.jpg",
].map((imageUrl, index) => ({
    friendID: "demo-self",
    imageUrl,
    name: demoProfile.fullName,
    postId: 100 - index,
    spaceId: "demo-self",
    timestampMs: 1_700_000_000_000 - index * 86_400_000,
    viewerLiked: false,
}));

interface CanvasSize {
    height: number;
    width: number;
}

interface LayoutDemoPostProps {
    count: number;
    index: number;
    placement: HomeTilePlacement;
}

const LayoutDemoPost: React.FC<LayoutDemoPostProps> = ({
    count,
    index,
    placement,
}) => {
    const showAllVariants = count >= 5;
    const friendRequestDirection = showAllVariants
        ? index == 0
            ? ("sent" as const)
            : index == 1
              ? ("received" as const)
              : undefined
        : count == 2 && index == 1
          ? ("sent" as const)
          : count >= 2 && index == 0
            ? ("received" as const)
            : undefined;
    const seenPostIndex = showAllVariants ? 2 : count >= 3 ? 1 : undefined;
    const unseenPostIndex = showAllVariants ? 3 : count >= 3 ? 2 : undefined;
    const hasPlaceholderMedia = index == seenPostIndex;
    const isUnread = index == unseenPostIndex;
    const username = friendRequestDirection
        ? friendRequestDirection == "sent"
            ? "request_pending"
            : "new_friend"
        : `friend${index + 1}`;
    const friend = {
        friendsCount: 0,
        fullName: `Friend ${index + 1}`,
        id: `demo-friend-${index + 1}`,
        username,
    };
    const post: SpacePost | undefined =
        hasPlaceholderMedia || isUnread
            ? {
                  friendID: friend.id,
                  name: friend.fullName,
                  postId: index + 1,
                  spaceId: friend.id,
                  timestampMs: 1_700_000_000_000 - index * 60_000,
                  username,
                  viewerLiked: false,
              }
            : undefined;

    return (
        <FriendPostTile
            avatarUrl={
                hasPlaceholderMedia ? "/images/default-profile-pic.png" : null
            }
            friend={friend}
            friendRequestDirection={friendRequestDirection}
            imageUrl={
                hasPlaceholderMedia
                    ? "/images/invite-bg.jpg"
                    : isUnread
                      ? spaceDefaultCoverImagePath
                      : undefined
            }
            isAvatarPending={false}
            isLoading={false}
            isRead={!isUnread}
            isUnavailable={false}
            onAcceptFriendRequest={
                friendRequestDirection == "received"
                    ? () => Promise.resolve()
                    : undefined
            }
            onDiscardFriendRequest={
                friendRequestDirection == "received"
                    ? () => Promise.resolve()
                    : undefined
            }
            onOpenFriendRequest={
                friendRequestDirection ? () => undefined : undefined
            }
            onOpenPosts={() => undefined}
            isTwoTileLayout={count == 2}
            placement={placement}
            posts={post ? [post] : []}
            showFriendRequestDetails={count <= 2}
        />
    );
};

const LayoutDemoPage: React.FC = () => {
    const router = useSpaceRouter();
    const [isAddFriendOpen, setIsAddFriendOpen] = React.useState(false);
    const [profileLink, setProfileLink] = React.useState<string>();
    const [{ friendCount, ownPosts }, setDemo] = React.useState({
        friendCount: 0,
        ownPosts: [] as SpacePost[],
    });
    const changeFriendCount = React.useCallback((delta: number) => {
        setDemo(({ friendCount }) => {
            const count = Math.max(
                0,
                Math.min(maximumHomeTileCount, friendCount + delta),
            );
            return {
                friendCount: count,
                ownPosts: count % 2 == 0 ? [] : demoOwnPosts,
            };
        });
    }, []);
    const [ownViewerPosts, setOwnViewerPosts] = React.useState<SpacePost[]>([]);
    const [ownPostIndex, setOwnPostIndex] = React.useState<number>();
    const ownViewerOpen = ownPostIndex !== undefined;
    useBrowserBackClose({
        open: ownViewerOpen,
        onClose: () => setOwnPostIndex(undefined),
        stateKey: "space-layout-demo-viewer",
    });
    const ownPostPhotos = ownViewerPosts.map((post) => ({
        ...post,
        alt: "Your post",
        avatarUrl: demoProfile.avatarUrl,
        imageUrl: post.imageUrl ?? "",
    }));
    const [canvasSize, setCanvasSize] = React.useState<CanvasSize>({
        height: 0,
        width: 0,
    });
    const canvasRef = React.useRef<HTMLDivElement | null>(null);

    React.useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas) return;

        const updateSize = () => {
            const { height, width } = canvas.getBoundingClientRect();
            setCanvasSize({ height, width });
        };
        const observer = new ResizeObserver(updateSize);
        observer.observe(canvas);
        updateSize();
        return () => observer.disconnect();
    }, []);

    React.useEffect(() => {
        if (ownViewerOpen || isAddFriendOpen) return;

        const handleKeyDown = (event: KeyboardEvent) => {
            if (event.key == "ArrowLeft") {
                changeFriendCount(-1);
            } else if (event.key == "ArrowRight") {
                changeFriendCount(1);
            }
        };
        window.addEventListener("keydown", handleKeyDown);
        return () => window.removeEventListener("keydown", handleKeyDown);
    }, [changeFriendCount, isAddFriendOpen, ownViewerOpen]);

    const layout = homeTileLayout(
        friendCount,
        canvasSize.width,
        canvasSize.height,
    );

    return (
        <Box
            component="main"
            sx={{
                background: spaceAppBackground,
                color: spaceText,
                display: "grid",
                minHeight: "100svh",
                overflowX: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
                position: "relative",
            }}
        >
            <Box
                sx={{
                    boxSizing: "border-box",
                    maxWidth: "100%",
                    minHeight: "100svh",
                    minWidth: 0,
                    mx: "auto",
                    overflowX: "hidden",
                    position: "relative",
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                <SpaceHomeHeader
                    onOpenSettings={() =>
                        void router.push(spaceRoutes.settings)
                    }
                />
                <Box
                    sx={{
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        gap: `${homeTileGap}px`,
                        minHeight: `calc(100svh - ${spaceHomeHeaderHeight}px)`,
                        minWidth: 0,
                        pb: "calc(env(safe-area-inset-bottom) + 16px)",
                        px: "16px",
                        pt: "4px",
                        width: "100%",
                    }}
                >
                    <Box
                        ref={canvasRef}
                        component="ul"
                        aria-label="Friends and friend requests"
                        sx={{
                            flex: "1 1 auto",
                            m: 0,
                            minHeight: minimumHomeTileCanvasHeight(friendCount),
                            p: 0,
                            position: "relative",
                            width: "100%",
                        }}
                    >
                        {layout && (
                            <>
                                {layout.friends.map((placement, index) => (
                                    <LayoutDemoPost
                                        key={index}
                                        count={friendCount}
                                        index={index}
                                        placement={placement}
                                    />
                                ))}
                                {layout.addFriend && (
                                    <SpaceAddFriendTile
                                        placement={layout.addFriend}
                                        variant={layout.addFriendVariant}
                                        onClick={() => {
                                            setProfileLink(
                                                spaceInviteURL({
                                                    spaceUsername:
                                                        demoProfile.username,
                                                }),
                                            );
                                            setIsAddFriendOpen(true);
                                        }}
                                    />
                                )}
                            </>
                        )}
                    </Box>
                    <Box
                        sx={{
                            ...spaceTileCornerStyles(spacePostTileRadius),
                            flexShrink: 0,
                            position: "relative",
                        }}
                    >
                        <SpaceOwnPostTile
                            profile={demoProfile}
                            post={ownPosts[0]}
                            onNewPost={() =>
                                setDemo((current) => ({
                                    ...current,
                                    ownPosts: demoOwnPosts,
                                }))
                            }
                            onOpenPost={() => {
                                setOwnViewerPosts(ownPosts);
                                setOwnPostIndex(0);
                            }}
                        />
                        <Box
                            sx={{
                                display: "flex",
                                gap: "8px",
                                position: "absolute",
                                right: spaceTileCircleInset(36),
                                top: spaceTileCircleInset(36),
                                zIndex: 5,
                            }}
                        >
                            <Box
                                component="button"
                                type="button"
                                aria-label="Show one fewer friend"
                                disabled={friendCount == 0}
                                onClick={() => changeFriendCount(-1)}
                                sx={{
                                    alignItems: "center",
                                    appearance: "none",
                                    bgcolor: controlButtonColor,
                                    border: 0,
                                    borderRadius: "50%",
                                    color: spaceText,
                                    cursor:
                                        friendCount == 0
                                            ? "default"
                                            : "pointer",
                                    display: "flex",
                                    height: 36,
                                    justifyContent: "center",
                                    opacity: friendCount == 0 ? 0.3 : 1,
                                    p: 0,
                                    width: 36,
                                }}
                            >
                                <HugeiconsIcon
                                    icon={ArrowLeft02Icon}
                                    size={22}
                                    strokeWidth={2.2}
                                />
                            </Box>
                            <Box
                                component="button"
                                type="button"
                                aria-label="Show one more friend"
                                disabled={friendCount == maximumHomeTileCount}
                                onClick={() => changeFriendCount(1)}
                                sx={{
                                    alignItems: "center",
                                    appearance: "none",
                                    bgcolor: controlButtonColor,
                                    border: 0,
                                    borderRadius: "50%",
                                    color: spaceText,
                                    cursor:
                                        friendCount == maximumHomeTileCount
                                            ? "default"
                                            : "pointer",
                                    display: "flex",
                                    height: 36,
                                    justifyContent: "center",
                                    opacity:
                                        friendCount == maximumHomeTileCount
                                            ? 0.3
                                            : 1,
                                    p: 0,
                                    width: 36,
                                }}
                            >
                                <HugeiconsIcon
                                    icon={ArrowRight02Icon}
                                    size={22}
                                    strokeWidth={2.2}
                                />
                            </Box>
                        </Box>
                    </Box>
                </Box>
                <SpaceAddFriendDialog
                    friendRequests={[]}
                    friends={[]}
                    open={isAddFriendOpen}
                    onClose={() => setIsAddFriendOpen(false)}
                    onAddFriend={() => {
                        changeFriendCount(1);
                        return Promise.resolve("requested");
                    }}
                    profileLink={profileLink}
                    username={demoProfile.username}
                />
                {ownPostIndex !== undefined && (
                    <SpaceFileViewer
                        photo={ownPostPhotos[ownPostIndex]!}
                        photos={ownPostPhotos}
                        photoIndex={ownPostIndex}
                        onPhotoIndexChange={setOwnPostIndex}
                        postActionMode="hidden"
                        onClose={() => setOwnPostIndex(undefined)}
                        onDeletePost={() => {
                            const postId = ownViewerPosts[ownPostIndex]!.postId;
                            setDemo((current) => ({
                                ...current,
                                ownPosts: current.ownPosts.filter(
                                    (post) => post.postId != postId,
                                ),
                            }));
                        }}
                        onUpdatePostCaption={(postId, caption) => {
                            const updatePosts = (posts: SpacePost[]) =>
                                posts.map((post) =>
                                    post.postId == postId
                                        ? {
                                              ...post,
                                              caption:
                                                  caption.trim() || undefined,
                                          }
                                        : post,
                                );
                            setDemo((current) => ({
                                ...current,
                                ownPosts: updatePosts(current.ownPosts),
                            }));
                            setOwnViewerPosts(updatePosts);
                            return Promise.resolve();
                        }}
                    />
                )}
            </Box>
        </Box>
    );
};

export default LayoutDemoPage;
