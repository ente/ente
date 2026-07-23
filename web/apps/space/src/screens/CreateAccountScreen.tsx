import { Box } from "@mui/material";
import { SpaceBackIcon } from "components/SpaceBackIcon";
import { SpaceButtonSpinner } from "components/SpaceButtonSpinner";
import {
    estimatePasswordStrength,
    type PasswordStrength,
} from "ente-accounts-rs/utils/password";
import React, { useId, useMemo, useState } from "react";
import { spaceTouchTargetSize } from "styles/touchTargets";

export const createAccountBackground = "#FAFAFA";

const green = "#08C225";
const textBase = "#000";
const textLight = "#969696";
const warning = "#F63A3A";
const caution = "#B65F00";
const createAccountFormID = "space-create-account-form";

const passwordStrengthLabels: Record<PasswordStrength, string> = {
    weak: "Weak",
    moderate: "Moderate",
    strong: "Strong",
};

export interface CreateAccountInput {
    email: string;
    password: string;
    referralSource: string;
}

interface CreateAccountScreenProps {
    errorMessage?: string;
    isSubmitting?: boolean;
    onBack: () => void;
    onCreateAccount: (input: CreateAccountInput) => void;
}

interface TextInputProps {
    autoComplete?: string;
    label: string;
    labelAccessory?: React.ReactNode;
    onChange?: (value: string) => void;
    placeholder?: string;
    required?: boolean;
    type?: "email" | "password" | "text";
    value?: string;
}

const EyeIcon: React.FC = () => (
    <Box
        component="svg"
        viewBox="0 0 24 24"
        aria-hidden
        sx={{ display: "block", height: 24, width: 24 }}
    >
        <path
            d="M2.75 12S6.25 6.75 12 6.75S21.25 12 21.25 12S17.75 17.25 12 17.25S2.75 12 2.75 12Z"
            fill="none"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="1.8"
        />
        <circle
            cx="12"
            cy="12"
            fill="none"
            r="2.75"
            stroke="currentColor"
            strokeWidth="1.8"
        />
    </Box>
);

const CheckIcon: React.FC = () => (
    <Box
        component="svg"
        viewBox="0 0 16 16"
        aria-hidden
        sx={{ display: "block", height: 14, width: 14 }}
    >
        <path
            d="M3.25 8.25L6.25 11.25L12.75 4.75"
            fill="none"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="2"
        />
    </Box>
);

const XIcon: React.FC = () => (
    <Box
        component="svg"
        viewBox="0 0 16 16"
        aria-hidden
        sx={{ display: "block", height: 14, width: 14 }}
    >
        <path
            d="M4.25 4.25L11.75 11.75M11.75 4.25L4.25 11.75"
            fill="none"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="2"
        />
    </Box>
);

const AlertIcon: React.FC = () => (
    <Box
        component="svg"
        viewBox="0 0 16 16"
        aria-hidden
        sx={{ display: "block", height: 14, width: 14 }}
    >
        <path
            d="M8 2.75L14 13.25H2L8 2.75Z"
            fill="none"
            stroke="currentColor"
            strokeLinejoin="round"
            strokeWidth="1.6"
        />
        <path
            d="M8 6.25V9M8 11.25H8.01"
            fill="none"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.8"
        />
    </Box>
);

const StatusLabel: React.FC<{
    icon: React.ReactNode;
    label: string;
    tone: "critical" | "success" | "warning";
}> = ({ icon, label, tone }) => {
    const color =
        tone == "critical" ? warning : tone == "warning" ? caution : green;

    return (
        <Box
            aria-live="polite"
            sx={{
                alignItems: "center",
                color,
                display: "flex",
                flexShrink: 0,
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 12,
                fontWeight: 600,
                gap: "4px",
                lineHeight: "16px",
            }}
        >
            {icon}
            <Box component="span">{label}</Box>
        </Box>
    );
};

const TextInput: React.FC<TextInputProps> = ({
    autoComplete,
    label,
    labelAccessory,
    onChange,
    placeholder,
    required,
    type = "text",
    value,
}) => {
    const inputID = useId();
    const [showPassword, setShowPassword] = useState(false);
    const isPassword = type == "password";

    return (
        <Box sx={{ width: "100%" }}>
            <Box
                component="label"
                htmlFor={inputID}
                sx={{
                    alignItems: "center",
                    color: textBase,
                    display: "flex",
                    fontFamily: '"Inter Variable", Inter, sans-serif',
                    fontSize: 14,
                    fontWeight: 500,
                    gap: "2px",
                    justifyContent: "space-between",
                    lineHeight: "20px",
                    mb: "9px",
                }}
            >
                <Box sx={{ display: "flex", gap: "2px", minWidth: 0 }}>
                    <Box component="span">{label}</Box>
                    {required && <Box sx={{ color: warning }}>*</Box>}
                </Box>
                {labelAccessory}
            </Box>
            <Box
                sx={{
                    alignItems: "center",
                    bgcolor: "white",
                    borderRadius: "16px",
                    display: "flex",
                    height: 52,
                    px: 2,
                    width: "100%",
                    "&:focus-within": {
                        outline: `2px solid ${green}`,
                        outlineOffset: 1,
                    },
                }}
            >
                <Box
                    component="input"
                    autoComplete={autoComplete}
                    id={inputID}
                    onChange={(event) => onChange?.(event.target.value)}
                    placeholder={placeholder}
                    required={required}
                    type={isPassword && showPassword ? "text" : type}
                    value={value}
                    sx={{
                        bgcolor: "transparent",
                        border: 0,
                        color: textBase,
                        flex: 1,
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 14,
                        fontWeight: 500,
                        lineHeight: "20px",
                        minWidth: 0,
                        outline: 0,
                        p: 0,
                        "&::placeholder": { color: textLight, opacity: 1 },
                    }}
                />
                {isPassword && (
                    <Box
                        component="button"
                        type="button"
                        aria-label={
                            showPassword ? "Hide password" : "Show password"
                        }
                        onClick={() => setShowPassword((value) => !value)}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: textLight,
                            cursor: "pointer",
                            display: "flex",
                            flexShrink: 0,
                            height: spaceTouchTargetSize,
                            justifyContent: "center",
                            mr: -0.5,
                            p: 0,
                            width: spaceTouchTargetSize,
                            "&:focus-visible": {
                                borderRadius: "50%",
                                outline: `2px solid ${green}`,
                                outlineOffset: 1,
                            },
                        }}
                    >
                        <EyeIcon />
                    </Box>
                )}
            </Box>
        </Box>
    );
};

export const CreateAccountScreen: React.FC<CreateAccountScreenProps> = ({
    errorMessage,
    isSubmitting = false,
    onBack,
    onCreateAccount,
}) => {
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    const [confirmPassword, setConfirmPassword] = useState("");
    const [referralSource, setReferralSource] = useState("");
    const [acceptedTerms, setAcceptedTerms] = useState(true);
    const passwordStrength = useMemo(
        () => estimatePasswordStrength(password),
        [password],
    );
    const hasWeakPassword = password.length > 0 && passwordStrength == "weak";
    const passwordHelperTone =
        passwordStrength == "weak"
            ? "critical"
            : passwordStrength == "moderate"
              ? "warning"
              : "success";
    const passwordStrengthIcon =
        passwordStrength == "weak" ? (
            <XIcon />
        ) : passwordStrength == "moderate" ? (
            <AlertIcon />
        ) : (
            <CheckIcon />
        );
    const isConfirmPasswordFilled = confirmPassword.length > 0;
    const doPasswordsMatch = password == confirmPassword;

    const canCreateAccount =
        !isSubmitting &&
        email.trim().length > 0 &&
        password.length > 0 &&
        !hasWeakPassword &&
        confirmPassword.length > 0 &&
        password == confirmPassword &&
        acceptedTerms;
    const isCreateAccountButtonActive = canCreateAccount || isSubmitting;

    const submitCreateAccount = () => {
        if (canCreateAccount) {
            onCreateAccount({ email: email.trim(), password, referralSource });
        }
    };

    const handleSubmit: React.SubmitEventHandler<HTMLFormElement> = (event) => {
        event.preventDefault();
        submitCreateAccount();
    };

    return (
        <Box
            component="main"
            sx={{
                bgcolor: createAccountBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflow: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
            }}
        >
            <Box
                sx={{
                    bgcolor: createAccountBackground,
                    boxSizing: "border-box",
                    display: "flex",
                    flexDirection: "column",
                    minHeight: "100svh",
                    mx: "auto",
                    pb: "154px",
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
                        Create an account
                    </Box>
                    <Box />
                </Box>

                <Box
                    component="form"
                    id={createAccountFormID}
                    onSubmit={handleSubmit}
                    sx={{
                        display: "flex",
                        flexDirection: "column",
                        gap: "24px",
                        mt: "20px",
                        width: "100%",
                    }}
                >
                    <TextInput
                        autoComplete="username"
                        label="Email"
                        onChange={setEmail}
                        placeholder="Enter your email"
                        required
                        type="email"
                        value={email}
                    />
                    <TextInput
                        autoComplete="new-password"
                        labelAccessory={
                            password ? (
                                <StatusLabel
                                    icon={passwordStrengthIcon}
                                    label={
                                        passwordStrengthLabels[passwordStrength]
                                    }
                                    tone={passwordHelperTone}
                                />
                            ) : undefined
                        }
                        label="Password"
                        onChange={setPassword}
                        placeholder="Enter your password"
                        required
                        type="password"
                        value={password}
                    />
                    <TextInput
                        autoComplete="new-password"
                        label="Confirm Password"
                        labelAccessory={
                            isConfirmPasswordFilled ? (
                                <StatusLabel
                                    icon={
                                        doPasswordsMatch ? (
                                            <CheckIcon />
                                        ) : (
                                            <XIcon />
                                        )
                                    }
                                    label={
                                        doPasswordsMatch ? "Match" : "No match"
                                    }
                                    tone={
                                        doPasswordsMatch
                                            ? "success"
                                            : "critical"
                                    }
                                />
                            ) : undefined
                        }
                        onChange={setConfirmPassword}
                        placeholder="Re-enter your password"
                        required
                        type="password"
                        value={confirmPassword}
                    />
                    <TextInput
                        label="How did you hear about Ente?"
                        onChange={setReferralSource}
                        value={referralSource}
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
                                mt: "-8px",
                            }}
                        >
                            {errorMessage}
                        </Box>
                    )}
                    <Box
                        component="label"
                        sx={{
                            alignItems: "flex-start",
                            color: textLight,
                            cursor: "pointer",
                            display: "flex",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 500,
                            gap: "10px",
                            lineHeight: "17px",
                            width: "100%",
                        }}
                    >
                        <Box
                            className={acceptedTerms ? "green-bg" : undefined}
                            sx={{
                                alignItems: "center",
                                bgcolor: acceptedTerms ? green : "transparent",
                                border: `1px solid ${
                                    acceptedTerms ? green : textLight
                                }`,
                                borderRadius: "4px",
                                color: "white",
                                display: "flex",
                                flexShrink: 0,
                                height: 16,
                                justifyContent: "center",
                                mt: "1px",
                                position: "relative",
                                width: 16,
                            }}
                        >
                            <Box
                                component="input"
                                checked={acceptedTerms}
                                onChange={(event) =>
                                    setAcceptedTerms(event.target.checked)
                                }
                                type="checkbox"
                                sx={{
                                    appearance: "none",
                                    cursor: "pointer",
                                    height: 16,
                                    inset: 0,
                                    m: 0,
                                    opacity: 0,
                                    position: "absolute",
                                    width: 16,
                                    "&:focus-visible": {
                                        outline: `2px solid ${green}`,
                                        outlineOffset: 3,
                                    },
                                }}
                            />
                            {acceptedTerms && <CheckIcon />}
                        </Box>
                        <Box>
                            I accept the{" "}
                            <Box
                                component="a"
                                href="https://ente.io/terms"
                                sx={{
                                    color: "inherit",
                                    textDecoration: "underline",
                                }}
                            >
                                terms
                            </Box>{" "}
                            and{" "}
                            <Box
                                component="a"
                                href="https://ente.io/privacy"
                                sx={{
                                    color: "inherit",
                                    textDecoration: "underline",
                                }}
                            >
                                privacy policy
                            </Box>
                            .
                        </Box>
                    </Box>
                </Box>

                <Box
                    sx={{
                        bgcolor: createAccountBackground,
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
                        className={
                            isCreateAccountButtonActive ? "green-bg" : undefined
                        }
                        component="button"
                        form={createAccountFormID}
                        type="submit"
                        disabled={!canCreateAccount}
                        aria-label={
                            isSubmitting ? "Creating account" : undefined
                        }
                        aria-busy={isSubmitting ? true : undefined}
                        sx={{
                            alignItems: "center",
                            bgcolor: isCreateAccountButtonActive
                                ? green
                                : "#F5F5F5",
                            border: 0,
                            borderRadius: "20px",
                            color: isCreateAccountButtonActive
                                ? "white"
                                : textLight,
                            cursor: canCreateAccount ? "pointer" : "default",
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
                            "&:hover": canCreateAccount
                                ? { bgcolor: "#07AE22" }
                                : undefined,
                        }}
                    >
                        {isSubmitting ? (
                            <SpaceButtonSpinner />
                        ) : (
                            "Create an account"
                        )}
                    </Box>
                </Box>
            </Box>
        </Box>
    );
};
