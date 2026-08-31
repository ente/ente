import { Box, Dialog, useMediaQuery } from "@mui/material";
import { SpaceBottomSheetTransition } from "components/BottomSheetTransition";
import log from "ente-base/log";
import React from "react";
import {
    onOpenSpaceShareLinkDialog,
    type SpaceShareLinkDialogMode,
} from "services/share-link";

const green = "#08C225";
const dangerColor = "#F63A3A";

const isMobileBrowser = () => {
    const { maxTouchPoints, userAgent } = navigator;
    return (
        /Android|iPad|iPhone|iPod/i.test(userAgent) ||
        (userAgent.includes("Macintosh") && maxTouchPoints > 1)
    );
};

export const SpaceShareLinkDialogHost: React.FC = () => {
    const isBottomSheet = useMediaQuery("(max-width: 599px)");
    const [open, setOpen] = React.useState(false);
    const [profileLink, setProfileLink] = React.useState("");
    const [error, setError] = React.useState<string>();
    const [copied, setCopied] = React.useState(false);
    const [useNativeShare, setUseNativeShare] = React.useState(false);
    const [mode, setMode] = React.useState<SpaceShareLinkDialogMode>("profile");

    const showLink = React.useCallback(
        (nextMode: SpaceShareLinkDialogMode, nextProfileLink: string) => {
            setOpen(true);
            setMode(nextMode);
            setProfileLink(nextProfileLink);
            setError(undefined);
            setCopied(false);
            setUseNativeShare(
                isMobileBrowser() && typeof navigator.share == "function",
            );
        },
        [],
    );

    React.useEffect(() => {
        return onOpenSpaceShareLinkDialog(showLink);
    }, [showLink]);

    const close = () => {
        setProfileLink("");
        setOpen(false);
    };

    const copy = async () => {
        if (!profileLink) return;
        try {
            await navigator.clipboard.writeText(profileLink);
            setCopied(true);
        } catch (error) {
            log.error("Failed to copy Space link", error);
            setError("Couldn't copy the link.");
        }
    };

    const share = async () => {
        if (!profileLink) return;
        if (!useNativeShare) {
            await copy();
            return;
        }
        try {
            await navigator.share({ url: profileLink });
        } catch (error) {
            if (
                !(error instanceof DOMException && error.name == "AbortError")
            ) {
                log.error("Failed to share Space link", error);
                setError("Couldn't share the link.");
            }
        }
    };

    return (
        <Dialog
            open={open}
            onClose={close}
            maxWidth={false}
            slots={
                isBottomSheet
                    ? { transition: SpaceBottomSheetTransition }
                    : undefined
            }
            slotProps={{
                paper: {
                    sx: {
                        bgcolor: "#FAFAFA",
                        borderRadius: "28px 28px 0 0",
                        bottom: 0,
                        boxShadow: "none",
                        boxSizing: "border-box",
                        left: 0,
                        m: 0,
                        maxWidth: "none",
                        p: "26px 20px 24px",
                        position: "fixed",
                        width: "100vw",
                        "@media (min-width: 600px)": {
                            borderRadius: "20px",
                            bottom: "auto",
                            left: "50%",
                            maxWidth: 363,
                            top: "50%",
                            transform: "translate(-50%, -50%)",
                            width: 363,
                        },
                    },
                },
            }}
        >
            <Box
                sx={{
                    maxWidth: 320,
                    mx: "auto",
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: "none" },
                }}
            >
                <Box
                    component="h2"
                    sx={{
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 15,
                        fontWeight: 600,
                        lineHeight: "20px",
                        m: 0,
                        px: "20px",
                        textAlign: "center",
                    }}
                >
                    {mode == "invite" ? "Invite friends" : "Share your profile"}
                </Box>
                <Box
                    sx={{
                        color: "#666",
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 13,
                        lineHeight: "18px",
                        mt: "8px",
                        mx: "-10px",
                        px: 0,
                        textAlign: "center",
                    }}
                >
                    Let friends and family add you as a friend on Space
                </Box>
                <Box
                    sx={{
                        display: "flex",
                        flexDirection: "column",
                        gap: "12px",
                        mt: "20px",
                    }}
                >
                    <ActionButton
                        disabled={!profileLink}
                        label={
                            copied
                                ? "Copied"
                                : useNativeShare
                                  ? "Share profile"
                                  : "Copy link"
                        }
                        onClick={share}
                    />
                    {error && (
                        <Box
                            role="alert"
                            sx={{
                                color: dangerColor,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 13,
                                fontWeight: 600,
                                lineHeight: "18px",
                                px: "12px",
                                textAlign: "center",
                            }}
                        >
                            {error}
                        </Box>
                    )}
                </Box>
            </Box>
        </Dialog>
    );
};

interface ActionButtonProps {
    disabled?: boolean;
    label: string;
    onClick: () => void | Promise<void>;
}

const ActionButton: React.FC<ActionButtonProps> = ({
    disabled,
    label,
    onClick,
}) => (
    <Box
        className="green-bg"
        component="button"
        type="button"
        disabled={disabled}
        onClick={() => void onClick()}
        sx={{
            alignItems: "center",
            bgcolor: green,
            border: 0,
            borderRadius: "20px",
            color: "#FFF",
            cursor: disabled ? "default" : "pointer",
            display: "flex",
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 14,
            fontWeight: 600,
            height: 48,
            justifyContent: "center",
            lineHeight: "20px",
            opacity: disabled ? 0.5 : 1,
            px: "24px",
            transition: "filter 120ms ease, opacity 120ms ease",
            width: "100%",
            "&:active": disabled ? undefined : { filter: "brightness(0.96)" },
            "&:focus-visible": {
                outline: `2px solid ${green}`,
                outlineOffset: 2,
            },
            "&:hover": disabled ? undefined : { filter: "brightness(0.98)" },
        }}
    >
        {label}
    </Box>
);
