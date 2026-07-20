import { Box } from "@mui/material";
import { SpaceBackIcon } from "components/SpaceBackIcon";
import { SpaceButtonSpinner } from "components/SpaceButtonSpinner";
import React from "react";
import { spaceTouchTargetSize } from "styles/touchTargets";

export const passkeyVerificationBackground = "#FAFAFA";

const green = "#08C225";
const primaryLight = "#DDEEDF";
const primaryDark = "#069D1E";
const textBase = "#000";
const warning = "#F63A3A";

export type PasskeyVerificationStatus = "waiting" | "checking" | "pending";

interface PasskeyVerificationScreenProps {
    canUseTwoFactor?: boolean;
    errorMessage?: string;
    onBack: () => void;
    onCheckStatus: () => void;
    onTryAgain: () => void;
    onUseTwoFactor?: () => void;
    status?: PasskeyVerificationStatus;
}

const statusText = (status: PasskeyVerificationStatus) => {
    switch (status) {
        case "checking":
            return "Checking verification...";
        case "pending":
            return "Verification still pending";
        case "waiting":
            return "Waiting for verification...";
    }
};

export const PasskeyVerificationScreen: React.FC<
    PasskeyVerificationScreenProps
> = ({
    canUseTwoFactor = false,
    errorMessage,
    onBack,
    onCheckStatus,
    onTryAgain,
    onUseTwoFactor,
    status = "waiting",
}) => {
    const isChecking = status == "checking";

    return (
        <Box
            component="main"
            sx={{
                bgcolor: passkeyVerificationBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflow: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
            }}
        >
            <Box
                sx={{
                    bgcolor: passkeyVerificationBackground,
                    boxSizing: "border-box",
                    display: "flex",
                    flexDirection: "column",
                    minHeight: "100svh",
                    mx: "auto",
                    pb: "216px",
                    px: 3,
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                <Box
                    component="header"
                    sx={{
                        display: "grid",
                        gridTemplateColumns: `${spaceTouchTargetSize}px 1fr ${spaceTouchTargetSize}px`,
                        height: spaceTouchTargetSize,
                        mt: "32px",
                        width: "100%",
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label="Back"
                        onClick={onBack}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: textBase,
                            cursor: "pointer",
                            display: "flex",
                            height: spaceTouchTargetSize,
                            justifyContent: "flex-start",
                            p: 0,
                            width: spaceTouchTargetSize,
                            "&:focus-visible": {
                                borderRadius: "50%",
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <SpaceBackIcon />
                    </Box>
                    <Box
                        component="h1"
                        sx={{
                            alignSelf: "center",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 20,
                            fontWeight: 600,
                            justifySelf: "center",
                            lineHeight: "28px",
                            m: 0,
                            whiteSpace: "nowrap",
                        }}
                    >
                        Passkey verification
                    </Box>
                    <Box />
                </Box>

                <Box
                    sx={{
                        alignItems: "center",
                        display: "flex",
                        flex: 1,
                        flexDirection: "column",
                        justifyContent: "center",
                        mb: "56px",
                        width: "100%",
                    }}
                >
                    <Box
                        sx={{
                            alignItems: "center",
                            display: "flex",
                            flexDirection: "column",
                            gap: "8px",
                            textAlign: "center",
                            width: "100%",
                        }}
                    >
                        <Box
                            sx={{
                                color: textBase,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 500,
                                lineHeight: "20px",
                                minHeight: "20px",
                            }}
                        >
                            {statusText(status)}
                        </Box>
                        {canUseTwoFactor && onUseTwoFactor && (
                            <Box
                                component="button"
                                type="button"
                                onClick={onUseTwoFactor}
                                sx={{
                                    bgcolor: "transparent",
                                    border: 0,
                                    color: green,
                                    cursor: "pointer",
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 14,
                                    fontWeight: 500,
                                    lineHeight: "20px",
                                    p: 0,
                                    textDecoration: "underline",
                                }}
                            >
                                Use 2FA instead
                            </Box>
                        )}
                        {errorMessage && (
                            <Box
                                role="alert"
                                sx={{
                                    color: warning,
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 13,
                                    fontWeight: 500,
                                    lineHeight: "18px",
                                    mt: "8px",
                                    maxWidth: 298,
                                }}
                            >
                                {errorMessage}
                            </Box>
                        )}
                    </Box>
                </Box>

                <Box
                    sx={{
                        bgcolor: passkeyVerificationBackground,
                        bottom: 0,
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        gap: "16px",
                        left: "50%",
                        maxWidth: 390,
                        p: 3,
                        position: "fixed",
                        transform: "translateX(-50%)",
                        width: "100%",
                    }}
                >
                    <Box
                        className="green-bg"
                        component="button"
                        type="button"
                        onClick={onTryAgain}
                        sx={{
                            alignItems: "center",
                            bgcolor: green,
                            border: 0,
                            borderRadius: "20px",
                            color: "white",
                            cursor: "pointer",
                            display: "flex",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 500,
                            height: 48,
                            justifyContent: "center",
                            lineHeight: "20px",
                            p: "14px 24px",
                            width: "100%",
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 3,
                            },
                            "&:hover": { bgcolor: "#07AE22" },
                        }}
                    >
                        Try again
                    </Box>
                    <Box
                        component="button"
                        type="button"
                        disabled={isChecking}
                        aria-label={isChecking ? "Checking status" : undefined}
                        aria-busy={isChecking ? true : undefined}
                        onClick={onCheckStatus}
                        sx={{
                            alignItems: "center",
                            bgcolor: primaryLight,
                            border: 0,
                            borderRadius: "20px",
                            color: primaryDark,
                            cursor: isChecking ? "default" : "pointer",
                            display: "flex",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 500,
                            height: 48,
                            justifyContent: "center",
                            lineHeight: "20px",
                            p: "14px 24px",
                            width: "100%",
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 3,
                            },
                        }}
                    >
                        {isChecking ? <SpaceButtonSpinner /> : "Check status"}
                    </Box>
                </Box>
            </Box>
        </Box>
    );
};
