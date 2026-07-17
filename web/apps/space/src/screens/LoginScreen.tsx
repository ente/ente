import { Box } from "@mui/material";
import { SpaceBackIcon } from "components/SpaceBackIcon";
import { SpaceButtonSpinner } from "components/SpaceButtonSpinner";
import React, { useEffect, useRef, useState } from "react";
import { spaceTouchTargetSize } from "styles/touchTargets";

export const loginBackground = "#FAFAFA";

const green = "#08C225";
const textBase = "#000";
const textLight = "#969696";
const warning = "#F63A3A";
const loginFormID = "space-login-form";

export interface SpaceLoginCredentials {
    email: string;
    password: string;
}

interface LoginScreenProps {
    errorMessage?: string;
    focusPassword?: boolean;
    initialEmail?: string;
    isSubmitting?: boolean;
    onBack?: () => void;
    onChangeEmail?: () => void;
    onContinue?: (credentials: SpaceLoginCredentials) => Promise<void> | void;
    readOnlyEmail?: boolean;
    showBack?: boolean;
    title?: string;
}

interface TextInputProps {
    autoFocus?: boolean;
    inputRef?: React.Ref<HTMLInputElement>;
    label: string;
    onChange?: (value: string) => void;
    placeholder?: string;
    readOnly?: boolean;
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

const TextInput: React.FC<TextInputProps> = ({
    autoFocus,
    inputRef,
    label,
    onChange,
    placeholder,
    readOnly = false,
    required,
    type = "text",
    value,
}) => {
    const [showPassword, setShowPassword] = useState(false);
    const internalInputRef = useRef<HTMLInputElement | null>(null);
    const isPassword = type == "password";
    const setInputRef = (element: HTMLInputElement | null) => {
        internalInputRef.current = element;
        if (typeof inputRef == "function") {
            inputRef(element);
        } else if (inputRef) {
            inputRef.current = element;
        }
    };

    const togglePasswordVisibility = () => {
        const inputElement = internalInputRef.current;
        const shouldRestoreFocus = document.activeElement == inputElement;

        setShowPassword((value) => !value);
        if (shouldRestoreFocus) {
            window.requestAnimationFrame(() =>
                inputElement?.focus({ preventScroll: true }),
            );
        }
    };

    return (
        <Box sx={{ width: "100%" }}>
            <Box
                component="label"
                sx={{
                    color: textBase,
                    display: "flex",
                    fontFamily: '"Inter Variable", Inter, sans-serif',
                    fontSize: 14,
                    fontWeight: 500,
                    gap: "2px",
                    lineHeight: "20px",
                    mb: "9px",
                }}
            >
                {label}
                {required && <Box sx={{ color: warning }}>*</Box>}
            </Box>
            <Box
                sx={{
                    alignItems: "center",
                    bgcolor: readOnly ? "#F5F5F5" : "white",
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
                    ref={setInputRef}
                    autoFocus={autoFocus}
                    onChange={(event) => onChange?.(event.target.value)}
                    placeholder={placeholder}
                    readOnly={readOnly}
                    type={isPassword && showPassword ? "text" : type}
                    value={value}
                    sx={{
                        bgcolor: "transparent",
                        border: 0,
                        color: textBase,
                        cursor: readOnly ? "default" : undefined,
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
                        onClick={togglePasswordVisibility}
                        onPointerDown={(event) => event.preventDefault()}
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

const FooterLinkButton: React.FC<{
    children: React.ReactNode;
    disabled?: boolean;
    onClick?: () => void;
}> = ({ children, disabled = false, onClick }) => (
    <Box
        component="button"
        type="button"
        disabled={disabled}
        onClick={onClick}
        sx={{
            alignItems: "center",
            bgcolor: "transparent",
            border: 0,
            color: "#666",
            cursor: disabled ? "default" : "pointer",
            display: "flex",
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 14,
            fontWeight: 500,
            justifyContent: "center",
            lineHeight: "20px",
            minWidth: 0,
            opacity: 0.8,
            p: 0,
            textAlign: "center",
            textDecoration: "underline",
            textDecorationSkipInk: "none",
            textUnderlineOffset: "2px",
            textUnderlinePosition: "from-font",
            width: "100%",
            "&:focus-visible": {
                borderRadius: "4px",
                outline: `2px solid ${green}`,
                outlineOffset: 4,
            },
        }}
    >
        {children}
    </Box>
);

export const LoginScreen: React.FC<LoginScreenProps> = ({
    errorMessage,
    focusPassword = false,
    initialEmail,
    isSubmitting = false,
    onBack,
    onChangeEmail,
    onContinue,
    readOnlyEmail = false,
    showBack = true,
    title = "Login",
}) => {
    const [email, setEmail] = useState(initialEmail ?? "");
    const [password, setPassword] = useState("");
    const passwordInputRef = useRef<HTMLInputElement | null>(null);
    const appliedInitialEmailRef = useRef<string | undefined>(initialEmail);

    useEffect(() => {
        if (!initialEmail || appliedInitialEmailRef.current == initialEmail) {
            return;
        }

        setEmail((currentEmail) =>
            currentEmail && !readOnlyEmail ? currentEmail : initialEmail,
        );
        appliedInitialEmailRef.current = initialEmail;
    }, [initialEmail, readOnlyEmail]);

    useEffect(() => {
        if (!focusPassword) return undefined;

        const animationFrame = window.requestAnimationFrame(() =>
            passwordInputRef.current?.focus(),
        );
        return () => window.cancelAnimationFrame(animationFrame);
    }, [focusPassword, initialEmail]);

    const canContinue =
        !isSubmitting && email.trim().length > 0 && password.length > 0;
    const isContinueButtonActive = canContinue || isSubmitting;

    const submitLogin = () => {
        if (canContinue) void onContinue?.({ email, password });
    };

    const handleContinuePointerDown: React.PointerEventHandler<
        HTMLButtonElement
    > = (event) => {
        if (event.pointerType != "touch") return;

        event.preventDefault();
        submitLogin();
        if (document.activeElement instanceof HTMLElement) {
            document.activeElement.blur();
        }
    };

    const handleSubmit: React.SubmitEventHandler<HTMLFormElement> = (event) => {
        event.preventDefault();
        submitLogin();
    };

    return (
        <Box
            component="main"
            sx={{
                bgcolor: loginBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                placeItems: { xs: "stretch", sm: "start center" },
            }}
        >
            <Box
                sx={{
                    bgcolor: loginBackground,
                    boxSizing: "border-box",
                    display: "flex",
                    flexDirection: "column",
                    minHeight: "100svh",
                    mx: "auto",
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
                    {showBack && onBack ? (
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
                    ) : (
                        <Box />
                    )}
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
                        {title}
                    </Box>
                    <Box />
                </Box>

                <Box
                    component="form"
                    id={loginFormID}
                    noValidate
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
                        label="Email"
                        onChange={readOnlyEmail ? undefined : setEmail}
                        placeholder="Enter your email"
                        readOnly={readOnlyEmail}
                        required
                        type="email"
                        value={email}
                    />
                    <TextInput
                        label="Password"
                        inputRef={passwordInputRef}
                        onChange={setPassword}
                        placeholder="Enter your password"
                        required
                        autoFocus={focusPassword}
                        type="password"
                        value={password}
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
                </Box>

                <Box
                    sx={{
                        bgcolor: loginBackground,
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        gap: "16px",
                        mt: "auto",
                        pb: "calc(24px + env(safe-area-inset-bottom))",
                        pt: 3,
                        width: "100%",
                    }}
                >
                    <Box
                        className={
                            isContinueButtonActive ? "green-bg" : undefined
                        }
                        component="button"
                        form={loginFormID}
                        type="submit"
                        disabled={!canContinue}
                        aria-label={isSubmitting ? "Signing in" : undefined}
                        aria-busy={isSubmitting ? true : undefined}
                        onPointerDown={handleContinuePointerDown}
                        sx={{
                            alignItems: "center",
                            bgcolor: isContinueButtonActive ? green : "#F5F5F5",
                            border: 0,
                            borderRadius: "20px",
                            color: isContinueButtonActive ? "white" : textLight,
                            cursor: canContinue ? "pointer" : "default",
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
                            "&:hover": canContinue
                                ? { bgcolor: "#07AE22" }
                                : undefined,
                        }}
                    >
                        {isSubmitting ? <SpaceButtonSpinner /> : "Continue"}
                    </Box>
                    {readOnlyEmail && onChangeEmail && (
                        <FooterLinkButton
                            disabled={isSubmitting}
                            onClick={onChangeEmail}
                        >
                            Change email
                        </FooterLinkButton>
                    )}
                </Box>
            </Box>
        </Box>
    );
};
