import { ArrowLeft02Icon, ArrowRight02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { SpaceAddFriendButton } from "components/AddFriendButton";
import { SpaceAddFriendDialog } from "components/AddFriendDialog";
import { SpaceAddFriendTile } from "components/AddFriendTile";
import { SpaceFileViewer } from "components/FileViewer";
import { SpaceHomeHeader, spaceHomeHeaderHeight } from "components/HomeHeader";
import { SpaceNewPostButton } from "components/NewPostButton";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React from "react";
import { FriendPostTile } from "screens/HomeScreen";
import type { SetupProfile } from "screens/SetupProfileScreen";
import { spaceInviteURL } from "services/invite";
import type { SpacePost } from "services/space";
import { spaceAppBackground, spaceText } from "styles/colors";
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

const demoProfile: SetupProfile = {
    avatarUrl: null,
    fullName: "Alex Morgan",
    spaceId: "demo-self",
    username: "you",
};

const singleFriendVariants = [
    "no-posts",
    "one-post",
    "three-posts",
    "received",
    "sent",
] as const;

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
    const [variantIndex, setVariantIndex] = React.useState(0);

    React.useEffect(() => {
        setVariantIndex(0);
        if (count != 1) return;

        const timer = window.setInterval(() => {
            setVariantIndex(
                (current) => (current + 1) % singleFriendVariants.length,
            );
        }, 3000);
        return () => window.clearInterval(timer);
    }, [count]);

    const singleFriendVariant =
        count == 1 ? singleFriendVariants[variantIndex] : undefined;
    const showAllVariants = count >= 5;
    const singleFriendRequestDirection =
        singleFriendVariant == "sent" || singleFriendVariant == "received"
            ? singleFriendVariant
            : undefined;
    const friendRequestDirection =
        count == 1
            ? singleFriendRequestDirection
            : showAllVariants
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
    const isUnread =
        count == 1
            ? singleFriendVariant == "one-post" ||
              singleFriendVariant == "three-posts"
            : index == unseenPostIndex;
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
    const posts: SpacePost[] =
        hasPlaceholderMedia || isUnread
            ? Array.from(
                  { length: singleFriendVariant == "three-posts" ? 3 : 1 },
                  (_, postIndex) => ({
                      friendID: friend.id,
                      name: friend.fullName,
                      postId: index + postIndex + 1,
                      spaceId: friend.id,
                      timestampMs:
                          1_700_000_000_000 - (index + postIndex) * 60_000,
                      username,
                      viewerLiked: false,
                  }),
              )
            : [];

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
            isNineTileLayout={count == maximumHomeTileCount}
            isTwoTileLayout={count == 2}
            placement={placement}
            posts={posts}
            showFriendRequestDetails={count <= 2}
        />
    );
};

const LayoutDemoPage: React.FC = () => {
    const router = useSpaceRouter();
    const [isAddFriendOpen, setIsAddFriendOpen] = React.useState(false);
    const [profileLink, setProfileLink] = React.useState<string>();
    const [friendCount, setFriendCount] = React.useState(0);
    const changeFriendCount = React.useCallback((delta: number) => {
        setFriendCount((count) =>
            Math.max(0, Math.min(maximumHomeTileCount, count + delta)),
        );
    }, []);
    const [isPostPreviewOpen, setIsPostPreviewOpen] = React.useState(false);
    useBrowserBackClose({
        open: isPostPreviewOpen,
        onClose: () => setIsPostPreviewOpen(false),
        stateKey: "space-layout-demo-viewer",
    });
    const [canvasSize, setCanvasSize] = React.useState<CanvasSize>({
        height: 0,
        width: 0,
    });
    const canvasRef = React.useRef<HTMLDivElement | null>(null);
    const openAddFriend = () => {
        setProfileLink(spaceInviteURL({ spaceUsername: demoProfile.username }));
        setIsAddFriendOpen(true);
    };

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
        if (isPostPreviewOpen || isAddFriendOpen) return;

        const handleKeyDown = (event: KeyboardEvent) => {
            if (event.key == "ArrowLeft") {
                changeFriendCount(-1);
            } else if (event.key == "ArrowRight") {
                changeFriendCount(1);
            }
        };
        window.addEventListener("keydown", handleKeyDown);
        return () => window.removeEventListener("keydown", handleKeyDown);
    }, [changeFriendCount, isAddFriendOpen, isPostPreviewOpen]);

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
                    logoActions={
                        <Box sx={{ display: "flex" }}>
                            <Box
                                component="button"
                                type="button"
                                aria-label="Show one fewer friend"
                                disabled={friendCount == 0}
                                onClick={() => changeFriendCount(-1)}
                                sx={{
                                    alignItems: "center",
                                    appearance: "none",
                                    bgcolor: "transparent",
                                    border: 0,
                                    borderRadius: "50%",
                                    color: spaceText,
                                    cursor:
                                        friendCount == 0
                                            ? "default"
                                            : "pointer",
                                    display: "flex",
                                    height: 24,
                                    justifyContent: "center",
                                    opacity: friendCount == 0 ? 0.3 : 1,
                                    p: 0,
                                    width: 24,
                                }}
                            >
                                <HugeiconsIcon
                                    icon={ArrowLeft02Icon}
                                    size={16}
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
                                    bgcolor: "transparent",
                                    border: 0,
                                    borderRadius: "50%",
                                    color: spaceText,
                                    cursor:
                                        friendCount == maximumHomeTileCount
                                            ? "default"
                                            : "pointer",
                                    display: "flex",
                                    height: 24,
                                    justifyContent: "center",
                                    opacity:
                                        friendCount == maximumHomeTileCount
                                            ? 0.3
                                            : 1,
                                    p: 0,
                                    width: 24,
                                }}
                            >
                                <HugeiconsIcon
                                    icon={ArrowRight02Icon}
                                    size={16}
                                    strokeWidth={2.2}
                                />
                            </Box>
                        </Box>
                    }
                    profile={demoProfile}
                    onOpenProfile={() => void router.push(spaceRoutes.profile)}
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
                                        onClick={openAddFriend}
                                    />
                                )}
                            </>
                        )}
                    </Box>
                    <Box
                        sx={{
                            alignItems: "center",
                            display: "flex",
                            gap: `${homeTileGap}px`,
                            justifyContent: "flex-end",
                        }}
                    >
                        {[1, 2, 4, 6, 8].includes(friendCount) && (
                            <SpaceAddFriendButton onClick={openAddFriend} />
                        )}
                        <SpaceNewPostButton
                            onClick={() => setIsPostPreviewOpen(true)}
                        />
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
                {isPostPreviewOpen && (
                    <SpaceFileViewer
                        photo={{
                            alt: "Your post",
                            avatarUrl: demoProfile.avatarUrl,
                            imageUrl: spaceDefaultCoverImagePath,
                            name: demoProfile.fullName,
                            timestampMs: 1_700_000_000_000,
                        }}
                        postActionMode="draft-post"
                        onClose={() => setIsPostPreviewOpen(false)}
                        onPublishDraftPost={() => Promise.resolve()}
                    />
                )}
            </Box>
        </Box>
    );
};

export default LayoutDemoPage;
