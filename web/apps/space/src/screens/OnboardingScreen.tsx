import { Box } from "@mui/material";
import { SpaceMobileBestToast } from "components/SpaceMobileBestToast";
import React from "react";

export const onboardingGreen = "#08C225";
export const onboardingTitle = "Share everyday moments";
export const onboardingDescription =
    "A private space for sharing everyday moments with friends and family. No ads. No algorithms.";
export const addFriendOnboardingTitle = (username: string) => (
    <>
        {`See @${username}'s`}
        <br />
        everyday moments
    </>
);

const softGreen = "#E7F6E9";
const copyGreen = "#AAFFB8";

interface ActionButtonProps {
    children: React.ReactNode;
    onClick?: () => void;
    variant: "primary" | "secondary";
}

const ActionButton: React.FC<ActionButtonProps> = ({
    children,
    onClick,
    variant,
}) => (
    <Box
        component="button"
        type="button"
        onClick={onClick}
        sx={{
            alignItems: "center",
            bgcolor: variant == "primary" ? "black" : softGreen,
            border: 0,
            borderRadius: "20px",
            color: variant == "primary" ? "white" : onboardingGreen,
            cursor: "pointer",
            display: "flex",
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 14,
            fontWeight: 500,
            height: 48,
            justifyContent: "center",
            lineHeight: "20px",
            p: "14px 24px",
            textDecoration: "none",
            width: "100%",
            "&:focus-visible": {
                outline: "2px solid rgba(255 255 255 / 0.88)",
                outlineOffset: 3,
            },
            "&:hover": {
                bgcolor: variant == "primary" ? "#121212" : "#DDF2E0",
            },
        }}
    >
        {children}
    </Box>
);

interface OnboardingScreenProps {
    description?: string;
    onCreateAccount: () => void;
    onLogin?: () => void;
    title?: React.ReactNode;
}

export const OnboardingScreen: React.FC<OnboardingScreenProps> = ({
    description = onboardingDescription,
    onCreateAccount,
    onLogin,
    title = onboardingTitle,
}) => {
    return (
        <Box
            className="green-bg"
            component="main"
            sx={{
                bgcolor: onboardingGreen,
                color: "white",
                display: "grid",
                minHeight: "100svh",
                overflow: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
            }}
        >
            <Box
                className="green-bg"
                sx={{
                    alignItems: "center",
                    bgcolor: onboardingGreen,
                    boxSizing: "border-box",
                    display: "flex",
                    flexDirection: "column",
                    height: "100svh",
                    minHeight: "100svh",
                    mx: "auto",
                    overflow: "hidden",
                    px: 3,
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                <Box
                    component="header"
                    sx={{
                        alignItems: "center",
                        display: "grid",
                        flexShrink: 0,
                        gridTemplateColumns: "40px 1fr 40px",
                        height: 40,
                        mt: "clamp(24px, 5.5svh, 44px)",
                        width: "100%",
                    }}
                >
                    <Box />
                    <Box
                        sx={{
                            color: "white",
                            justifySelf: "center",
                            lineHeight: 0,
                        }}
                    >
                        <Box
                            component="img"
                            alt="Ente Space"
                            src="/images/space.svg"
                            sx={{ display: "block", height: 30, width: 101 }}
                        />
                    </Box>
                    <Box />
                </Box>
                <Box
                    sx={{
                        alignItems: "center",
                        display: "flex",
                        flexDirection: "column",
                        flex: "1 1 auto",
                        justifyContent: "center",
                        minHeight: 0,
                        overflow: "hidden",
                        width: "100%",
                    }}
                >
                    <Box
                        sx={{
                            alignItems: "center",
                            display: "flex",
                            flexDirection: "column",
                            flexShrink: 0,
                            justifyContent: "center",
                            minWidth: 0,
                            overflow: "hidden",
                            width: "100%",
                        }}
                    >
                        <Box
                            component="img"
                            alt=""
                            src="/images/ducky-space.svg"
                            sx={{
                                flexShrink: 0,
                                height: "clamp(132px, 29svh, 245.189px)",
                                maxWidth: "min(282px, 76vw)",
                                width: "auto",
                                "@media (max-width: 340px)": {
                                    height: "auto",
                                    width: "76vw",
                                },
                            }}
                        />
                        <Box
                            sx={{
                                alignItems: "center",
                                display: "flex",
                                flexDirection: "column",
                                flexShrink: 0,
                                mt: "clamp(28px, 7svh, 60px)",
                                textAlign: "center",
                                width: "100%",
                                "@media (min-height: 760px)": { mt: "92px" },
                            }}
                        >
                            <Box
                                component="h1"
                                sx={{
                                    fontFamily: "Nunito, sans-serif",
                                    fontSize: 24,
                                    fontWeight: 800,
                                    letterSpacing: 0,
                                    lineHeight: "29px",
                                    m: 0,
                                    maxWidth: 320,
                                    overflowWrap: "anywhere",
                                }}
                            >
                                {title}
                            </Box>
                            <Box
                                component="p"
                                sx={{
                                    color: copyGreen,
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 14,
                                    fontWeight: 500,
                                    lineHeight: "20px",
                                    m: 0,
                                    mt: "12px",
                                    width: "100%",
                                }}
                            >
                                {description}
                            </Box>
                        </Box>
                    </Box>
                </Box>
                <Box
                    sx={{
                        display: "flex",
                        flexDirection: "column",
                        flexShrink: 0,
                        gap: "12px",
                        mb: "calc(32px + env(safe-area-inset-bottom))",
                        width: "100%",
                        "@media (min-width: 600px)": { mb: "44px" },
                    }}
                >
                    <ActionButton variant="primary" onClick={onCreateAccount}>
                        Create an Ente account
                    </ActionButton>
                    <ActionButton variant="secondary" onClick={onLogin}>
                        Login to existing account
                    </ActionButton>
                </Box>
            </Box>
            <SpaceMobileBestToast />
        </Box>
    );
};
