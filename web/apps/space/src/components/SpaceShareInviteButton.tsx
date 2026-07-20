import { Share08Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, type SxProps, type Theme } from "@mui/material";
import React from "react";

type ShareInviteResult = "shared" | "copied" | "dismissed";
type ShareInvitePhase = "idle" | "sharing" | "copied";

const copiedLabelDurationMs = 1400;

const shareSpaceInviteLink = async (
    profileLink: string,
): Promise<ShareInviteResult> => {
    if (typeof navigator.share == "function") {
        try {
            await navigator.share({ url: profileLink });
            return "shared";
        } catch (error) {
            if (error instanceof DOMException && error.name == "AbortError") {
                return "dismissed";
            }
            throw error;
        }
    }

    await navigator.clipboard.writeText(profileLink);
    return "copied";
};

export const SpaceShareIcon: React.FC<{ strokeWidth?: number }> = ({
    strokeWidth = 1.8,
}) => <HugeiconsIcon icon={Share08Icon} size={18} strokeWidth={strokeWidth} />;

interface SpaceShareInviteButtonProps {
    className?: string;
    iconStrokeWidth?: number;
    profileLink?: string;
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
    profileLink,
    sharing,
    sx,
    onShareComplete,
    onShareError,
    onShareStart,
    onSharingChange,
}) => {
    const [phase, setPhase] = React.useState<ShareInvitePhase>("idle");
    const copiedResetTimeoutRef = React.useRef<number | undefined>(undefined);
    const shareInFlightRef = React.useRef(false);
    const isSharing = sharing ?? phase == "sharing";
    const isDisabled = isSharing || !profileLink;
    const buttonLabel =
        phase == "copied"
            ? "Invite link copied"
            : isSharing
              ? "Sharing invite..."
              : "Share invite";

    const setSharing = (nextSharing: boolean) => {
        if (sharing === undefined) setPhase(nextSharing ? "sharing" : "idle");
        onSharingChange?.(nextSharing);
    };

    const clearCopiedResetTimeout = React.useCallback(() => {
        if (copiedResetTimeoutRef.current === undefined) return;
        window.clearTimeout(copiedResetTimeoutRef.current);
        copiedResetTimeoutRef.current = undefined;
    }, []);

    React.useEffect(
        () => () => {
            clearCopiedResetTimeout();
        },
        [clearCopiedResetTimeout],
    );

    const shareInvite = async () => {
        if (isDisabled || shareInFlightRef.current || !profileLink) return;

        shareInFlightRef.current = true;
        clearCopiedResetTimeout();
        setPhase("idle");
        onShareStart?.();

        try {
            if (typeof navigator.share == "function") setSharing(true);
            const result = await shareSpaceInviteLink(profileLink);
            if (result == "shared") onShareComplete?.();
            if (result == "copied") {
                setPhase("copied");
                copiedResetTimeoutRef.current = window.setTimeout(() => {
                    setPhase("idle");
                    copiedResetTimeoutRef.current = undefined;
                    onShareComplete?.();
                }, copiedLabelDurationMs);
            }
        } catch (error) {
            if (onShareError) {
                onShareError(error);
            } else {
                throw error;
            }
        } finally {
            shareInFlightRef.current = false;
            if (typeof navigator.share == "function") setSharing(false);
        }
    };

    return (
        <Box
            className={className}
            component="button"
            type="button"
            disabled={isDisabled}
            onClick={() => void shareInvite()}
            sx={sx}
        >
            <SpaceShareIcon strokeWidth={iconStrokeWidth} />
            {buttonLabel}
        </Box>
    );
};
