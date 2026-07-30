import { Shield01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { SpaceBackIcon } from "components/SpaceBackIcon";
import { SpaceButtonSpinner } from "components/SpaceButtonSpinner";
import { SpaceOtpInput } from "components/SpaceOtpInput";
import React, { useEffect, useRef, useState } from "react";
import { spaceTouchTargetSize } from "styles/touchTargets";
import { sanitizeSpaceOTP, spaceOTPCodeLength } from "utils/spaceOtp";

export const verifyTwoFactorBackground = "#FAFAFA";

const green = "#08C225";
const textBase = "#000";
const textMuted = "#666";
const textLight = "#969696";
const warning = "#F63A3A";
const verifyTwoFactorFormID = "space-verify-two-factor-form";

interface VerifyTwoFactorScreenProps {
    codeResetKey?: number;
    errorMessage?: string;
    initialCode?: string;
    isSubmitting?: boolean;
    onBack: () => void;
    onVerify?: (code: string) => void;
}

export const VerifyTwoFactorScreen: React.FC<VerifyTwoFactorScreenProps> = ({
    codeResetKey = 0,
    errorMessage,
    initialCode = "",
    isSubmitting = false,
    onBack,
    onVerify,
}) => {
    const initialOTP = sanitizeSpaceOTP(initialCode);
    const [otp, setOtp] = useState(initialOTP);
    const inputRef = useRef<HTMLInputElement | null>(null);

    const otpComplete = otp.length == spaceOTPCodeLength;
    const canVerify = otpComplete && !isSubmitting;
    const isVerifyButtonActive = canVerify || isSubmitting;

    useEffect(() => {
        setOtp(initialOTP);
        const animationFrame = window.requestAnimationFrame(() => {
            inputRef.current?.focus();
        });

        return () => window.cancelAnimationFrame(animationFrame);
    }, [initialOTP]);

    useEffect(() => {
        if (!codeResetKey) return;

        setOtp("");
        inputRef.current?.focus();
    }, [codeResetKey]);

    const submitVerification = () => {
        if (canVerify) onVerify?.(otp);
    };

    const handleSubmit: React.SubmitEventHandler<HTMLFormElement> = (event) => {
        event.preventDefault();
        submitVerification();
    };

    return (
        <Box
            component="main"
            sx={{
                bgcolor: verifyTwoFactorBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflow: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
            }}
        >
            <Box
                sx={{
                    bgcolor: verifyTwoFactorBackground,
                    boxSizing: "border-box",
                    display: "flex",
                    flexDirection: "column",
                    minHeight: "100svh",
                    mx: "auto",
                    pb: "120px",
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
                        2FA verification
                    </Box>
                    <Box />
                </Box>

                <Box
                    component="form"
                    id={verifyTwoFactorFormID}
                    noValidate
                    onSubmit={handleSubmit}
                    sx={{
                        alignItems: "center",
                        display: "flex",
                        flexDirection: "column",
                        gap: "40px",
                        mt: "40px",
                        width: "100%",
                    }}
                >
                    <Box
                        sx={{
                            alignItems: "center",
                            color: green,
                            display: "flex",
                            height: 82,
                            justifyContent: "center",
                            width: 101,
                        }}
                    >
                        <HugeiconsIcon
                            icon={Shield01Icon}
                            size={64}
                            strokeWidth={1.6}
                        />
                    </Box>

                    <Box
                        sx={{
                            display: "flex",
                            flexDirection: "column",
                            gap: "24px",
                            width: "100%",
                        }}
                    >
                        <Box
                            sx={{
                                color: textMuted,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 500,
                                lineHeight: "20px",
                                mx: "auto",
                                maxWidth: 298,
                                textAlign: "center",
                                width: "100%",
                            }}
                        >
                            Enter the 6-digit code from your authenticator app
                        </Box>

                        <Box sx={{ width: "100%" }}>
                            <SpaceOtpInput
                                ref={inputRef}
                                ariaLabel="2FA code"
                                onChange={setOtp}
                                value={otp}
                            />
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
                                        mt: "12px",
                                        textAlign: "center",
                                    }}
                                >
                                    {errorMessage}
                                </Box>
                            )}
                        </Box>
                    </Box>
                </Box>

                <Box
                    sx={{
                        bgcolor: verifyTwoFactorBackground,
                        bottom: 0,
                        boxSizing: "border-box",
                        left: "50%",
                        maxWidth: 390,
                        p: 3,
                        position: "fixed",
                        transform: "translateX(-50%)",
                        width: "100%",
                    }}
                >
                    <Box
                        className={
                            isVerifyButtonActive ? "green-bg" : undefined
                        }
                        component="button"
                        form={verifyTwoFactorFormID}
                        type="submit"
                        disabled={!canVerify}
                        aria-label={isSubmitting ? "Verifying" : undefined}
                        aria-busy={isSubmitting ? true : undefined}
                        sx={{
                            alignItems: "center",
                            bgcolor: isVerifyButtonActive ? green : "#F5F5F5",
                            border: 0,
                            borderRadius: "20px",
                            color: isVerifyButtonActive ? "white" : textLight,
                            cursor: canVerify ? "pointer" : "default",
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
                            "&:hover": canVerify
                                ? { bgcolor: "#07AE22" }
                                : undefined,
                        }}
                    >
                        {isSubmitting ? <SpaceButtonSpinner /> : "Verify"}
                    </Box>
                </Box>
            </Box>
        </Box>
    );
};
