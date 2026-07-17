import { Box, Dialog, useMediaQuery } from "@mui/material";
import { SpaceBottomSheetTransition } from "components/SpaceBottomSheetTransition";
import { SpaceShareInviteButton } from "components/SpaceShareInviteButton";
import React from "react";

const textBase = "#000";
const textSoft = "#777777";
const dangerColor = "#F63A3A";

interface SpaceInviteFriendsDialogProps {
    open: boolean;
    profileLink?: string;
    sharing: boolean;
    onClose: () => void;
    onSharingChange: (sharing: boolean) => void;
}

export const SpaceInviteFriendsDialog: React.FC<
    SpaceInviteFriendsDialogProps
> = ({ open, profileLink, sharing, onClose, onSharingChange }) => {
    const titleID = React.useId();
    const isBottomSheet = useMediaQuery("(max-width: 599px)");
    const [shareErrorMessage, setShareErrorMessage] = React.useState<
        string | null
    >(null);

    React.useEffect(() => {
        if (open) setShareErrorMessage(null);
    }, [open]);

    return (
        <Dialog
            open={open}
            onClose={sharing ? undefined : onClose}
            maxWidth={false}
            aria-labelledby={titleID}
            slots={
                isBottomSheet
                    ? { transition: SpaceBottomSheetTransition }
                    : undefined
            }
            slotProps={{
                backdrop: { sx: { backgroundColor: "rgba(0, 0, 0, 0.48)" } },
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
                        p: "26px 20px calc(24px + env(safe-area-inset-bottom))",
                        position: "fixed",
                        width: "100vw",
                        "@media (min-width: 600px)": {
                            borderRadius: "20px",
                            bottom: "auto",
                            left: "50%",
                            maxWidth: 342,
                            p: "24px 20px 20px",
                            top: "50%",
                            transform: "translate(-50%, -50%)",
                            width: 342,
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
                    id={titleID}
                    sx={{
                        color: textBase,
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 15,
                        fontWeight: 600,
                        lineHeight: "20px",
                        m: 0,
                        px: "20px",
                        textAlign: "center",
                    }}
                >
                    Add friends on Space
                </Box>
                <Box
                    component="p"
                    sx={{
                        color: textSoft,
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 14,
                        fontWeight: 500,
                        lineHeight: "20px",
                        m: 0,
                        mt: "10px",
                        textAlign: "center",
                    }}
                >
                    Share your invite link with friends and family.
                </Box>
                <Box
                    sx={{
                        display: "flex",
                        flexDirection: "column",
                        gap: "10px",
                        mt: "22px",
                    }}
                >
                    <SpaceShareInviteButton
                        className="green-bg"
                        profileLink={profileLink}
                        sharing={sharing}
                        onShareComplete={onClose}
                        onShareError={(error) => {
                            console.error(
                                "Failed to share space invite",
                                error,
                            );
                            setShareErrorMessage(
                                "Couldn't share invite. Please try again.",
                            );
                        }}
                        onShareStart={() => setShareErrorMessage(null)}
                        onSharingChange={onSharingChange}
                        sx={{
                            alignItems: "center",
                            border: 0,
                            borderRadius: "20px",
                            color: "#FFFFFF",
                            cursor: sharing ? "default" : "pointer",
                            display: "flex",
                            gap: "10px",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 600,
                            height: 48,
                            justifyContent: "center",
                            lineHeight: "20px",
                            px: "24px",
                            py: "14px",
                            transition: "filter 120ms ease, opacity 120ms ease",
                            width: "100%",
                            "&:active": sharing
                                ? undefined
                                : { filter: "brightness(0.96)" },
                            "&:disabled": { opacity: 1 },
                            "&:focus-visible": {
                                outline: "2px solid rgba(0 0 0 / 0.72)",
                                outlineOffset: 2,
                            },
                            "&:hover": sharing
                                ? undefined
                                : { filter: "brightness(0.98)" },
                        }}
                    />
                    {shareErrorMessage && (
                        <Box
                            role="alert"
                            sx={{
                                color: dangerColor,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 13,
                                fontWeight: 650,
                                lineHeight: "18px",
                                textAlign: "center",
                            }}
                        >
                            {shareErrorMessage}
                        </Box>
                    )}
                </Box>
            </Box>
        </Dialog>
    );
};
