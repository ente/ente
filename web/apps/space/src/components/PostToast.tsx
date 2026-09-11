import { AlertCircleIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { SpaceActionFeedbackIcon } from "components/ActionFeedback";
import {
    SpaceActionToast,
    spaceToastAutoDismissDurationMs,
} from "components/ActionToast";
import React from "react";
import { useSpaceAppState } from "state/app-state";
import { spaceToastActionButtonSx } from "styles/buttons";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const dangerColor = "#F63A3A";

export const SpacePostToast: React.FC = () => {
    const router = useSpaceRouter();
    const { postPublication, setPostPublication } = useSpaceAppState();
    const dismissPostPublishToast = React.useCallback(() => {
        setPostPublication(null);
    }, [setPostPublication]);

    if (!postPublication) return null;

    const phase = postPublication.phase;
    const isPosting = phase == "posting";
    const isFailed = phase == "failed";
    const isPosted = phase == "posted";
    return (
        <SpaceActionToast
            action={
                isPosted && (
                    <Box
                        component="button"
                        type="button"
                        onClick={() => {
                            dismissPostPublishToast();
                            void router.push(
                                `${spaceRoutes.profile}?section=latest`,
                                undefined,
                                { scroll: false },
                            );
                        }}
                        sx={spaceToastActionButtonSx}
                    >
                        View post
                    </Box>
                )
            }
            animateEntrance={isPosting}
            autoDismissAfterMs={
                isFailed ? spaceToastAutoDismissDurationMs : undefined
            }
            closeLabel="Dismiss post status"
            icon={
                isFailed ? (
                    <HugeiconsIcon
                        color={dangerColor}
                        icon={AlertCircleIcon}
                        size={20}
                        strokeWidth={1.8}
                    />
                ) : (
                    <SpaceActionFeedbackIcon
                        phase={isPosting ? "busy" : "done"}
                        size={20}
                    />
                )
            }
            message={isPosting ? "Posting..." : isFailed ? "Failed" : "Posted"}
            onClose={dismissPostPublishToast}
            showCloseButton={isPosted}
            zIndex={1400}
        />
    );
};
