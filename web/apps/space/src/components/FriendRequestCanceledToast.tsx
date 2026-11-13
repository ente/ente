import { UserRemove01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    SpaceActionToast,
    spaceToastAutoDismissDurationMs,
} from "components/ActionToast";
import React from "react";

const dangerColor = "#F63A3A";

interface SpaceFriendRequestCanceledToastProps {
    onClose: () => void;
}

export const SpaceFriendRequestCanceledToast: React.FC<
    SpaceFriendRequestCanceledToastProps
> = ({ onClose }) => (
    <SpaceActionToast
        animateEntrance
        autoDismissAfterMs={spaceToastAutoDismissDurationMs}
        closeLabel="Dismiss canceled friend request"
        icon={
            <HugeiconsIcon
                color={dangerColor}
                icon={UserRemove01Icon}
                size={20}
                strokeWidth={2}
            />
        }
        message="Friend request was canceled"
        onClose={onClose}
    />
);
