import { Box, Dialog, useMediaQuery } from "@mui/material";
import { ConfirmationActionSheet } from "components/ConfirmationActionSheet";
import { SpaceBottomSheetTransition } from "components/SpaceBottomSheetTransition";
import log from "ente-base/log";
import React from "react";
import {
    getOrCreateCurrentSpaceLink,
    rotateCurrentSpaceLink,
    type CurrentSpaceLink,
} from "services/space";
import { spaceInviteURL } from "services/spaceInvite";
import {
    onOpenSpaceShareLinkDialog,
    type SpaceShareLinkDialogMode,
} from "services/spaceShareLink";

const green = "#08C225";
const dangerColor = "#F63A3A";

export const SpaceShareLinkDialogHost: React.FC = () => {
    const isBottomSheet = useMediaQuery("(max-width: 599px)");
    const linkRequestID = React.useRef(0);
    const [open, setOpen] = React.useState(false);
    const [link, setLink] = React.useState<CurrentSpaceLink>();
    const [loading, setLoading] = React.useState(false);
    const [error, setError] = React.useState<string>();
    const [copied, setCopied] = React.useState(false);
    const [linkChanged, setLinkChanged] = React.useState(false);
    const [mode, setMode] = React.useState<SpaceShareLinkDialogMode>("profile");
    const [isChangeConfirmationOpen, setIsChangeConfirmationOpen] =
        React.useState(false);
    const [confirming, setConfirming] = React.useState(false);

    const loadLink = React.useCallback((nextMode: SpaceShareLinkDialogMode) => {
        const requestID = ++linkRequestID.current;
        setOpen(true);
        setMode(nextMode);
        setLink(undefined);
        setLoading(true);
        setError(undefined);
        setCopied(false);
        setLinkChanged(false);
        void getOrCreateCurrentSpaceLink()
            .then((nextLink) => {
                if (linkRequestID.current == requestID) setLink(nextLink);
            })
            .catch((error: unknown) => {
                if (linkRequestID.current != requestID) return;
                log.error("Failed to create Space link", error);
                setError("Couldn't create the link. Please try again.");
            })
            .finally(() => {
                if (linkRequestID.current == requestID) setLoading(false);
            });
    }, []);

    React.useEffect(() => {
        return onOpenSpaceShareLinkDialog(loadLink);
    }, [loadLink]);

    const close = () => {
        linkRequestID.current++;
        setLink(undefined);
        setLoading(false);
        setOpen(false);
    };

    const url = link
        ? spaceInviteURL({
              accessKey: link.accessKey,
              spaceUsername: link.spaceSlug,
          })
        : "";

    const copy = async () => {
        if (!url) return;
        try {
            await navigator.clipboard.writeText(url);
            setCopied(true);
        } catch (error) {
            log.error("Failed to copy Space link", error);
            setError("Couldn't copy the link.");
        }
    };

    const share = async () => {
        if (!url) return;
        if (typeof navigator.share != "function") {
            await copy();
            return;
        }
        try {
            await navigator.share({ url });
        } catch (error) {
            if (
                !(error instanceof DOMException && error.name == "AbortError")
            ) {
                log.error("Failed to share Space link", error);
                setError("Couldn't share the link.");
            }
        }
    };

    const confirm = () => {
        if (confirming) return;
        setConfirming(true);
        setError(undefined);
        void rotateCurrentSpaceLink()
            .then((nextLink) => {
                setIsChangeConfirmationOpen(false);
                setLink(nextLink);
                setCopied(false);
                setLinkChanged(true);
            })
            .catch((error: unknown) => {
                log.error("Failed to change Space link", error);
                setIsChangeConfirmationOpen(false);
                setError("Couldn't change the link.");
            })
            .finally(() => setConfirming(false));
    };

    return (
        <>
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
                        {linkChanged
                            ? "New link is ready"
                            : mode == "invite"
                              ? "Invite friends"
                              : "Share your profile"}
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
                        {linkChanged
                            ? "Share it with friends and family. Only you and people with this link can see your posts."
                            : "Let friends and family see what you share on Space. Only you and people with this link can see your posts."}
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
                            disabled={!link || loading}
                            label={
                                copied
                                    ? "Link copied"
                                    : loading
                                      ? "Getting link…"
                                      : linkChanged
                                        ? "Share new link"
                                        : "Share profile"
                            }
                            onClick={share}
                            variant="primary"
                        />
                        <ActionButton
                            disabled={!link || loading}
                            label="Change link"
                            onClick={() => setIsChangeConfirmationOpen(true)}
                            variant="text"
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
            <ConfirmationActionSheet
                open={isChangeConfirmationOpen}
                title="Change profile link?"
                description="You'll get a new link to share. The current one will stop working for anyone with the link."
                confirmLabel="Change link"
                confirmBackgroundColor={green}
                confirmClassName="green-bg"
                confirmDisabled={confirming}
                confirmActionPhase={confirming ? "busy" : null}
                cancelDisabled={confirming}
                onCancel={() => {
                    if (!confirming) setIsChangeConfirmationOpen(false);
                }}
                onConfirm={confirm}
            />
        </>
    );
};

interface ActionButtonProps {
    disabled?: boolean;
    label: string;
    onClick: () => void | Promise<void>;
    variant: "primary" | "text";
}

const ActionButton: React.FC<ActionButtonProps> = ({
    disabled,
    label,
    onClick,
    variant,
}) => (
    <Box
        className={variant == "primary" ? "green-bg" : undefined}
        component="button"
        type="button"
        disabled={disabled}
        onClick={() => void onClick()}
        sx={{
            alignItems: "center",
            bgcolor: variant == "primary" ? green : "transparent",
            border: 0,
            borderRadius: "20px",
            color: variant == "primary" ? "#FFF" : "#8A8A8A",
            cursor: disabled ? "default" : "pointer",
            display: "flex",
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 14,
            fontWeight: 600,
            height: variant == "primary" ? 48 : 32,
            justifyContent: "center",
            lineHeight: "20px",
            opacity: disabled ? 0.5 : 1,
            px: variant == "primary" ? "24px" : 0,
            textDecoration: variant == "text" ? "underline" : "none",
            textUnderlineOffset: "3px",
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
