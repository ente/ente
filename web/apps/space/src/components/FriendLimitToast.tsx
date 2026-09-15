import { AlertCircleIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    SpaceActionToast,
    spaceToastAutoDismissDurationMs,
} from "components/ActionToast";
import React from "react";

const dangerColor = "#F63A3A";

interface SpaceFriendLimitToastProps {
    message: string;
    onClose: () => void;
}

export const SpaceFriendLimitToast: React.FC<SpaceFriendLimitToastProps> = ({
    message,
    onClose,
}) => (
    <SpaceActionToast
        animateEntrance
        autoDismissAfterMs={spaceToastAutoDismissDurationMs}
        closeLabel="Dismiss friend limit"
        icon={
            <HugeiconsIcon
                color={dangerColor}
                icon={AlertCircleIcon}
                size={20}
                strokeWidth={1.8}
            />
        }
        message={message}
        onClose={onClose}
    />
);
