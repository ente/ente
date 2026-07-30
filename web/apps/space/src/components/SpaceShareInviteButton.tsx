import { Share08Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, type SxProps, type Theme } from "@mui/material";
import React from "react";
import { openSpaceShareLinkDialog } from "services/spaceShareLink";

export const SpaceShareIcon: React.FC<{ strokeWidth?: number }> = ({
    strokeWidth = 1.8,
}) => <HugeiconsIcon icon={Share08Icon} size={18} strokeWidth={strokeWidth} />;

interface SpaceShareInviteButtonProps {
    className?: string;
    iconStrokeWidth?: number;
    label?: string;
    profileLink?: string;
    showIcon?: boolean;
    sharing?: boolean;
    sx?: SxProps<Theme>;
    onShareComplete?: () => void;
    onShareError?: (error: unknown) => void;
    onShareStart?: () => void;
    onSharingChange?: (sharing: boolean) => void;
}

export const SpaceShareInviteButton: React.FC<SpaceShareInviteButtonProps> = ({
    className,
    iconStrokeWidth,
    label,
    profileLink,
    showIcon = true,
    sharing,
    sx,
    onShareComplete,
    onShareError,
    onShareStart,
    onSharingChange,
}) => {
    const isSharing = sharing ?? false;
    const isDisabled = isSharing || !profileLink;
    const buttonLabel = label ?? "Share profile";

    const shareInvite = () => {
        if (isDisabled || !profileLink) return;
        onShareStart?.();
        try {
            onSharingChange?.(true);
            openSpaceShareLinkDialog("invite");
            onShareComplete?.();
        } catch (error) {
            onShareError?.(error);
        } finally {
            onSharingChange?.(false);
        }
    };

    return (
        <Box
            className={className}
            component="button"
            type="button"
            disabled={isDisabled}
            onClick={shareInvite}
            sx={sx}
        >
            {showIcon && <SpaceShareIcon strokeWidth={iconStrokeWidth} />}
            {buttonLabel}
        </Box>
    );
};
