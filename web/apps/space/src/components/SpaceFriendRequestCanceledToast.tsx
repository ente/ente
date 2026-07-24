import { UserRemove01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { SpaceActionToast } from "components/SpaceActionToast";
import React from "react";

interface SpaceFriendRequestCanceledToastProps {
    onClose: () => void;
}

export const SpaceFriendRequestCanceledToast: React.FC<
    SpaceFriendRequestCanceledToastProps
> = ({ onClose }) => (
    <SpaceActionToast
        animateEntrance
        closeLabel="Dismiss canceled friend request"
        icon={
            <HugeiconsIcon
                color="#000000"
                icon={UserRemove01Icon}
                size={20}
                strokeWidth={2}
            />
        }
        message="Friend request was canceled"
        onClose={onClose}
    />
);
