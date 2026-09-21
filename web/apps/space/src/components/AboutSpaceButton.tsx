import { Box, SwipeableDrawer } from "@mui/material";
import { SpaceAboutContent } from "components/AboutSpaceContent";
import {
    SpaceAddFriendButton,
    type SpaceAddFriendButtonProps,
} from "components/AddFriendButton";
import { SpaceBackIcon } from "components/BackIcon";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React, { useState } from "react";

export const SpaceAboutButton: React.FC<
    SpaceAddFriendButtonProps & { username: string }
> = ({ isAddingFriend, onAddFriend, showAddingFriendSpinner, username }) => {
    const [open, setOpen] = useState(false);
    const close = () => setOpen(false);

    const { clearBrowserBackState } = useBrowserBackClose({
        open,
        onClose: close,
        stateKey: "space-about",
    });

    const addFriend = async () => {
        await clearBrowserBackState("back");
        close();
        onAddFriend();
    };

    return (
        <>
            <Box
                component="button"
                type="button"
                onClick={() => setOpen(true)}
                sx={{
                    alignItems: "center",
                    bgcolor: "rgba(0, 0, 0, 0.28)",
                    border: 0,
                    borderRadius: "999px",
                    color: "white",
                    cursor: "pointer",
                    display: "flex",
                    fontFamily: '"Inter Variable", Inter, sans-serif',
                    fontSize: 12,
                    fontWeight: 500,
                    lineHeight: "18px",
                    p: "8px 16px",
                    "&:hover": { bgcolor: "rgba(0, 0, 0, 0.36)" },
                    "&:focus-visible": {
                        outline: "2px solid white",
                        outlineOffset: 3,
                    },
                }}
            >
                What&apos;s Ente Space?
            </Box>
            <SwipeableDrawer
                anchor="right"
                open={open}
                onOpen={() => setOpen(true)}
                onClose={close}
                disableSwipeToOpen
                hysteresis={0.2}
                elevation={0}
                slotProps={{
                    backdrop: { sx: { bgcolor: "transparent" } },
                    paper: {
                        role: "dialog",
                        "aria-modal": true,
                        "aria-label": "About Ente Space",
                        sx: {
                            bgcolor: "#F5F5F7",
                            backgroundImage: "none",
                            borderRadius: 0,
                            color: "black",
                            height: "100dvh",
                            overscrollBehaviorY: "contain",
                            width: "100%",
                        },
                    },
                }}
            >
                <Box
                    component="header"
                    sx={{
                        flexShrink: 0,
                        pt: "calc(10px + env(safe-area-inset-top))",
                        px: 2,
                    }}
                >
                    <Box
                        sx={{
                            alignItems: "center",
                            display: "grid",
                            gridTemplateColumns: "44px 1fr 44px",
                            maxWidth: 480,
                            mx: "auto",
                        }}
                    >
                        <Box
                            component="button"
                            type="button"
                            aria-label="Back to invite"
                            autoFocus
                            onClick={close}
                            sx={{
                                alignItems: "center",
                                bgcolor: "transparent",
                                border: 0,
                                borderRadius: "12px",
                                color: "black",
                                cursor: "pointer",
                                display: "flex",
                                height: 44,
                                justifyContent: "center",
                                ml: "-12px",
                                p: 0,
                                width: 44,
                                "&:hover": { bgcolor: "rgba(0, 0, 0, 0.06)" },
                                "&:focus-visible": {
                                    outline: "2px solid black",
                                    outlineOffset: 3,
                                },
                            }}
                        >
                            <SpaceBackIcon />
                        </Box>
                        <Box
                            component="h1"
                            sx={{
                                fontFamily: "Nunito, sans-serif",
                                fontSize: 16,
                                fontWeight: 700,
                                lineHeight: "24px",
                                m: 0,
                                textAlign: "center",
                            }}
                        >
                            Ente Space
                        </Box>
                    </Box>
                </Box>
                <Box
                    sx={{
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        gap: 3,
                        flexShrink: 0,
                        pt: 1.25,
                        pb: "calc(32px + env(safe-area-inset-bottom))",
                        px: 2,
                    }}
                >
                    <Box
                        sx={{
                            display: "flex",
                            flexDirection: "column",
                            gap: 3,
                            maxWidth: 480,
                            mx: "auto",
                            width: "100%",
                        }}
                    >
                        <SpaceAboutContent>
                            <SpaceAddFriendButton
                                fullWidth
                                isAddingFriend={isAddingFriend}
                                label={`Add @${username} as friend`}
                                onAddFriend={() => void addFriend()}
                                showAddingFriendSpinner={
                                    showAddingFriendSpinner
                                }
                            />
                        </SpaceAboutContent>
                    </Box>
                </Box>
            </SwipeableDrawer>
        </>
    );
};
