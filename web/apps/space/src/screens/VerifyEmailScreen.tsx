import { Box } from "@mui/material";
import { SpaceBackIcon } from "components/SpaceBackIcon";
import { SpaceButtonSpinner } from "components/SpaceButtonSpinner";
import { SpaceOtpInput } from "components/SpaceOtpInput";
import React, { useEffect, useRef, useState } from "react";
import { spaceTouchTargetSize } from "styles/touchTargets";
import { sanitizeSpaceOTP, spaceOTPCodeLength } from "utils/spaceOtp";

export const verifyEmailBackground = "#FAFAFA";

const green = "#08C225";
const textBase = "#000";
const textMuted = "#666";
const textLight = "#969696";
const warning = "#F63A3A";
const verifyEmailFormID = "space-verify-email-form";

interface VerifyEmailScreenProps {
    codeResetKey?: number;
    email: string;
    errorMessage?: string;
    initialCode?: string;
    isResending?: boolean;
    isSubmitting?: boolean;
    onBack: () => void;
    onChangeEmail: () => void;
    onResendCode?: () => void;
    onVerify?: (code: string) => void;
}

export const VerifyEmailScreen: React.FC<VerifyEmailScreenProps> = ({
    codeResetKey = 0,
    email,
    errorMessage,
    initialCode = "",
    isResending = false,
    isSubmitting = false,
    onBack,
    onChangeEmail,
    onResendCode,
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

    const handleResendCode = () => {
        if (isResending) return;

        setOtp("");
        inputRef.current?.focus();
        onResendCode?.();
    };

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
                bgcolor: verifyEmailBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflow: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
            }}
        >
            <Box
                sx={{
                    bgcolor: verifyEmailBackground,
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
                        Verify email
                    </Box>
                    <Box />
                </Box>

                <Box
                    component="form"
                    id={verifyEmailFormID}
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
                        component="img"
                        alt=""
                        src="/images/verify-email.svg"
                        sx={{ height: 82, objectFit: "contain", width: 101 }}
                    />

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
                                display: "flex",
                                flexDirection: "column",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 500,
                                gap: "4px",
                                lineHeight: "20px",
                                textAlign: "center",
                                width: "100%",
                            }}
                        >
                            <Box sx={{ color: textBase }}>
                                We have sent a code to{" "}
                                {email || "example@example.com"}
                            </Box>
                            <Box
                                sx={{
                                    color: textMuted,
                                    mx: "auto",
                                    maxWidth: 298,
                                }}
                            >
                                Please check your inbox (and spam) to complete
                                verification
                            </Box>
                        </Box>

                        <Box sx={{ width: "100%" }}>
                            <SpaceOtpInput
                                ref={inputRef}
                                ariaLabel="Verification code"
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

                            <Box
                                sx={{
                                    alignItems: "center",
                                    display: "flex",
                                    justifyContent: "space-between",
                                    mt: "24px",
                                    width: "100%",
                                }}
                            >
                                <Box
                                    component="button"
                                    type="button"
                                    onClick={onChangeEmail}
                                    sx={{
                                        bgcolor: "transparent",
                                        border: 0,
                                        color: textLight,
                                        cursor: "pointer",
                                        display: "inline-flex",
                                        fontFamily:
                                            '"Inter Variable", Inter, sans-serif',
                                        fontSize: 14,
                                        fontWeight: 500,
                                        alignItems: "center",
                                        lineHeight: "20px",
                                        minHeight: spaceTouchTargetSize,
                                        p: 0,
                                        textDecoration: "underline",
                                        textUnderlineOffset: "2px",
                                    }}
                                >
                                    Change email
                                </Box>
                                {onResendCode && (
                                    <Box
                                        component="button"
                                        type="button"
                                        disabled={isResending}
                                        aria-label={
                                            isResending
                                                ? "Resending code"
                                                : undefined
                                        }
                                        aria-busy={
                                            isResending ? true : undefined
                                        }
                                        onClick={handleResendCode}
                                        sx={{
                                            bgcolor: "transparent",
                                            border: 0,
                                            color: green,
                                            cursor: isResending
                                                ? "default"
                                                : "pointer",
                                            display: "inline-flex",
                                            fontFamily:
                                                '"Inter Variable", Inter, sans-serif',
                                            fontSize: 14,
                                            fontWeight: 500,
                                            alignItems: "center",
                                            lineHeight: "20px",
                                            minHeight: spaceTouchTargetSize,
                                            minWidth: 84,
                                            p: 0,
                                            textDecoration: "underline",
                                            textUnderlineOffset: "2px",
                                        }}
                                    >
                                        {isResending ? (
                                            <SpaceButtonSpinner />
                                        ) : (
                                            "Resend code"
                                        )}
                                    </Box>
                                )}
                            </Box>
                        </Box>
                    </Box>
                </Box>

                <Box
                    sx={{
                        bgcolor: verifyEmailBackground,
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
                        form={verifyEmailFormID}
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
