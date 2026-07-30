import {
    Box,
    CircularProgress,
    Stack,
    TextField,
    Typography,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { ShowHidePasswordInputAdornment } from "ente-base/components/mui/PasswordInputAdornment";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { t } from "i18next";
import type { ReactNode } from "react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
    attemptDeviceLockUnlock,
    attemptUnlock,
    type DeviceLockUnlockResult,
    type UnlockResult,
} from "../../services/app-lock";
import { useAppLockSnapshot } from "../utils/use-snapshot";
import { AppLockCard } from "./AppLockCard";
import { CooldownScreen, ErrorMessage } from "./AppLockFeedback";
import { LockIllustration } from "./AppLockIllustrations";
import { LOGOUT_MODAL_WIDTH, subtitleTextSx, titleTextSx } from "./styles";

type AppLockSnapshot = ReturnType<typeof useAppLockSnapshot>;

interface AppLockUnlockFormProps {
    appLock: AppLockSnapshot;
    isReauthentication: boolean;
    onLogout: () => void;
    closeAction?: ReactNode;
}

interface UnlockContentProps extends AppLockUnlockFormProps {
    logout: () => void;
}

interface AppLockFormHeaderProps {
    title: string;
    subtitle: string;
    isReauthentication: boolean;
    marginBottom: number;
}

type UnlockInputError = string | null | undefined;

const ENTE_GREEN = "#08C225";
const ENTE_GREEN_HOVER = "#07A820";
const appLockModalContentSx = { width: 408 - 32, maxWidth: "100%" } as const;

const useCooldownState = (
    cooldownExpiresAt: number,
): { remainingMs: number; text: string | undefined } => {
    const [remaining, setRemaining] = useState<number>(
        Math.max(0, cooldownExpiresAt - Date.now()),
    );

    useEffect(() => {
        if (cooldownExpiresAt <= 0) {
            setRemaining(0);
            return;
        }

        const update = () => {
            const nextRemaining = Math.max(0, cooldownExpiresAt - Date.now());
            setRemaining(nextRemaining);
        };
        update();

        const interval = setInterval(update, 1000);
        return () => clearInterval(interval);
    }, [cooldownExpiresAt]);

    if (remaining <= 0) {
        return { remainingMs: remaining, text: undefined };
    }

    const totalSeconds = Math.ceil(remaining / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;

    return {
        remainingMs: remaining,
        text:
            minutes > 0
                ? `${String(minutes)}m ${String(seconds)}s`
                : `${String(seconds)}s`,
    };
};

const moveCaretToInputEnd = (input: HTMLInputElement) => {
    try {
        const caretPosition = input.value.length;
        input.setSelectionRange(caretPosition, caretPosition);
    } catch {
        // Ignore if selection range isn't supported.
    }
};

const primaryActionButtonSx = (theme: Parameters<typeof titleTextSx>[0]) => ({
    display: "flex",
    minHeight: 56,
    padding: "18px 16px",
    justifyContent: "center",
    alignItems: "center",
    gap: 1,
    borderRadius: "20px",
    backgroundColor: ENTE_GREEN,
    fontSize: 16,
    fontWeight: 500,
    lineHeight: "20px",
    textTransform: "none" as const,
    color: "#fff",
    boxShadow: "none",
    "&:hover": { backgroundColor: ENTE_GREEN_HOVER, boxShadow: "none" },
    "&.Mui-disabled": {
        backgroundColor: "rgba(0, 0, 0, 0.04)",
        color: "#999",
        opacity: 1,
    },
    ...theme.applyStyles("dark", {
        "&.Mui-disabled": {
            backgroundColor: "rgba(255, 255, 255, 0.08)",
            color: "rgba(255, 255, 255, 0.5)",
            opacity: 1,
        },
    }),
});

const inputFieldSx = (
    theme: Parameters<typeof titleTextSx>[0],
    options?: { borderRadius?: number },
) => ({
    borderRadius: options?.borderRadius ?? 12,
    "& .MuiInputBase-root": {
        height: 54,
        borderRadius: `${String(options?.borderRadius ?? 12)}px !important`,
        overflow: "hidden",
    },
    "& .MuiInput-root": {
        height: 54,
        backgroundColor: "#FAFAFA",
        borderRadius: `${String(options?.borderRadius ?? 12)}px !important`,
        "&::before": { borderBottom: "1px solid #E0E0E0" },
        "&::after": { borderBottom: `2px solid ${ENTE_GREEN}` },
        "&.Mui-error::before": { borderBottomColor: theme.palette.error.main },
        "&.Mui-error::after": { borderBottomColor: theme.palette.error.main },
        "&.Mui-error:hover:not(.Mui-disabled)::before": {
            borderBottomColor: theme.palette.error.main,
        },
        "&:hover:not(.Mui-disabled)::before": {
            borderBottom: "1px solid #BDBDBD",
        },
    },
    "& .MuiInputBase-input": {
        padding: "0 16px",
        height: "100%",
        boxSizing: "border-box" as const,
        fontSize: 16,
        color: "#000",
        "&::placeholder": { color: "#999", opacity: 1 },
    },
    ...theme.applyStyles("dark", {
        "& .MuiInput-root": {
            backgroundColor: "rgba(255, 255, 255, 0.08)",
            "&::before": { borderBottom: "1px solid rgba(255, 255, 255, 0.3)" },
            "&:hover:not(.Mui-disabled)::before": {
                borderBottom: "1px solid rgba(255, 255, 255, 0.5)",
            },
        },
        "& .MuiInputBase-root": {
            backgroundColor: "rgba(255, 255, 255, 0.08)",
        },
        "& .MuiInputBase-input": {
            color: "#fff",
            "&::placeholder": { color: "rgba(255, 255, 255, 0.5)" },
        },
    }),
});

const deviceLockErrorText = (result: DeviceLockUnlockResult) => {
    if (result.status === "success") return undefined;

    if (result.status === "not-supported") {
        switch (result.reason) {
            case "touchid-temporarily-unavailable":
            case "touchid-api-error":
                return t("device_lock_login_failed");
            case "unsupported-platform":
            case "touchid-not-enrolled":
                return t("device_lock_not_supported");
        }
    }

    switch (result.reason) {
        case "native-prompt-failed":
            return t("device_lock_login_cancelled");
        default:
            return t("device_lock_login_failed");
    }
};

const handleUnlockResult = (
    result: UnlockResult,
    setError: (error: UnlockInputError) => void,
    setLoading: (loading: boolean) => void,
    logout: () => void,
) => {
    switch (result) {
        case "success":
        case "cooldown":
            setError(undefined);
            setLoading(false);
            break;
        case "logout":
            logout();
            setLoading(false);
            break;
        case "failed":
            setError(null);
            setLoading(false);
            break;
    }
};

const AppLockFormHeader = ({
    title,
    subtitle,
    isReauthentication,
    marginBottom,
}: AppLockFormHeaderProps) => (
    <>
        <Box
            sx={{
                mt: -0.5,
                mb: 1.5,
                display: "flex",
                justifyContent: "center",
                width: "100%",
            }}
        >
            <LockIllustration />
        </Box>

        <Box
            sx={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: "9px",
                textAlign: "center",
                mb: marginBottom,
            }}
        >
            <Typography
                sx={(theme) => ({
                    ...titleTextSx(theme),
                    ...(isReauthentication ? {} : { mb: 0.5 }),
                })}
            >
                {title}
            </Typography>
            <Typography sx={subtitleTextSx}>{subtitle}</Typography>
        </Box>
    </>
);

const PinUnlockContent = ({
    appLock,
    isReauthentication,
    onLogout,
    closeAction,
    logout,
}: UnlockContentProps) => {
    const [pin, setPin] = useState(["", "", "", ""]);
    const [error, setError] = useState<UnlockInputError>();
    const [loading, setLoading] = useState(false);
    const inputRefs = useRef<(HTMLInputElement | null)[]>([]);
    const isSubmittingRef = useRef(false);
    const hasAutoSubmittedRef = useRef(false);
    const cooldown = useCooldownState(appLock.cooldownExpiresAt);

    const handlePinChange = useCallback(
        (index: number, value: string) => {
            const digit = value.replace(/\D/g, "").slice(-1);
            const nextPin = [...pin];
            nextPin[index] = digit;
            setPin(nextPin);
            setError(undefined);

            if (digit && index < 3) {
                inputRefs.current[index + 1]?.focus();
            }
        },
        [pin],
    );

    const handleKeyDown = useCallback(
        (index: number, e: React.KeyboardEvent) => {
            if (e.key === "Backspace" && !pin[index] && index > 0) {
                inputRefs.current[index - 1]?.focus();
            }
        },
        [pin],
    );

    const fullPin = useMemo(() => pin.join(""), [pin]);

    const focusPinInput = useCallback((pinIndex: number) => {
        const input = inputRefs.current[pinIndex];
        if (!input) return;

        input.focus({ preventScroll: true });
        moveCaretToInputEnd(input);
    }, []);

    const focusFirstEmptyPinInput = useCallback(() => {
        const firstEmptyIndex = pin.findIndex((digit) => !digit);
        focusPinInput(firstEmptyIndex === -1 ? 0 : firstEmptyIndex);
    }, [pin, focusPinInput]);

    const handleSubmit = useCallback(async () => {
        if (fullPin.length !== 4 || loading || isSubmittingRef.current) return;

        isSubmittingRef.current = true;
        setLoading(true);
        try {
            const result = await attemptUnlock(fullPin);
            handleUnlockResult(result, setError, setLoading, logout);
        } catch (e) {
            log.error("Unlock attempt failed", e);
            setError(t("generic_error"));
            setLoading(false);
        } finally {
            isSubmittingRef.current = false;
        }

        setPin(["", "", "", ""]);
        focusPinInput(0);
    }, [focusPinInput, fullPin, loading, logout]);

    useEffect(() => {
        if (fullPin.length !== 4) {
            hasAutoSubmittedRef.current = false;
            return;
        }

        if (loading || hasAutoSubmittedRef.current) return;

        hasAutoSubmittedRef.current = true;
        void handleSubmit();
    }, [fullPin, handleSubmit, loading]);

    useEffect(() => {
        if (error === undefined || loading || cooldown.text) return;

        const rafID = requestAnimationFrame(() => {
            focusPinInput(0);
        });
        return () => cancelAnimationFrame(rafID);
    }, [cooldown.text, error, focusPinInput, loading]);

    if (cooldown.text) {
        return (
            <AppLockCard closeAction={closeAction} width={LOGOUT_MODAL_WIDTH}>
                <CooldownScreen
                    remainingMs={cooldown.remainingMs}
                    cooldownText={cooldown.text}
                    attemptCount={appLock.invalidAttemptCount}
                    onLogout={onLogout}
                />
            </AppLockCard>
        );
    }

    return (
        <Stack spacing={0} useFlexGap sx={{ alignItems: "center" }}>
            <AppLockCard closeAction={closeAction}>
                <Stack
                    spacing={0}
                    useFlexGap
                    sx={[{ alignItems: "center" }, appLockModalContentSx]}
                >
                    <AppLockFormHeader
                        title={
                            isReauthentication
                                ? t("authenticate")
                                : t("app_locked")
                        }
                        subtitle={t("app_lock_enter_pin_to_unlock")}
                        isReauthentication={isReauthentication}
                        marginBottom={4}
                    />

                    <Stack
                        direction="row"
                        spacing={1.25}
                        onClick={focusFirstEmptyPinInput}
                        sx={{ justifyContent: "center", mb: 0, width: "100%" }}
                    >
                        {pin.map((digit, i) => (
                            <TextField
                                key={i}
                                variant="standard"
                                hiddenLabel
                                autoFocus={i === 0}
                                error={error !== undefined}
                                inputRef={(el: HTMLInputElement | null) => {
                                    inputRefs.current[i] = el;
                                }}
                                value={digit}
                                onChange={(e) =>
                                    handlePinChange(i, e.target.value)
                                }
                                onKeyDown={(e) => handleKeyDown(i, e)}
                                disabled={loading}
                                slotProps={{
                                    htmlInput: {
                                        maxLength: 1,
                                        inputMode: "numeric",
                                        pattern: "[0-9]",
                                        autoComplete: "off",
                                        style: {
                                            textAlign: "center",
                                            WebkitTextSecurity: "disc",
                                        },
                                        "aria-label": t(
                                            "app_lock_pin_digit_label",
                                            { index: i + 1 },
                                        ),
                                    },
                                }}
                                sx={(theme) => ({
                                    ...inputFieldSx(theme, {
                                        borderRadius: 12,
                                    }),
                                    flex: 1,
                                    minWidth: 0,
                                    "& .MuiInputBase-input": {
                                        padding: 0,
                                        textAlign: "center",
                                        height: "100%",
                                        fontSize: 20,
                                        fontWeight: 600,
                                    },
                                })}
                            />
                        ))}
                    </Stack>
                </Stack>
            </AppLockCard>

            <ErrorMessage
                error={error ?? undefined}
                attemptCount={appLock.invalidAttemptCount}
            />
        </Stack>
    );
};

const PasswordUnlockContent = ({
    appLock,
    isReauthentication,
    onLogout,
    closeAction,
    logout,
}: UnlockContentProps) => {
    const [password, setPassword] = useState("");
    const [showPassword, setShowPassword] = useState(false);
    const [error, setError] = useState<UnlockInputError>();
    const [loading, setLoading] = useState(false);
    const inputRef = useRef<HTMLInputElement | null>(null);
    const cooldown = useCooldownState(appLock.cooldownExpiresAt);

    const handleSubmit = useCallback(
        async (e?: React.SubmitEvent) => {
            e?.preventDefault();
            if (!password || loading) return;

            setLoading(true);
            try {
                const result = await attemptUnlock(password);
                handleUnlockResult(result, setError, setLoading, logout);
            } catch (e) {
                log.error("Unlock attempt failed", e);
                setError(t("generic_error"));
                setLoading(false);
            }

            setPassword("");
            inputRef.current?.focus();
        },
        [loading, logout, password],
    );

    useEffect(() => {
        if (error === undefined || loading || cooldown.text) return;

        const rafID = requestAnimationFrame(() => {
            inputRef.current?.focus();
        });
        return () => cancelAnimationFrame(rafID);
    }, [cooldown.text, error, loading]);

    if (cooldown.text) {
        return (
            <AppLockCard closeAction={closeAction} width={LOGOUT_MODAL_WIDTH}>
                <CooldownScreen
                    remainingMs={cooldown.remainingMs}
                    cooldownText={cooldown.text}
                    attemptCount={appLock.invalidAttemptCount}
                    onLogout={onLogout}
                />
            </AppLockCard>
        );
    }

    return (
        <Stack spacing={0} useFlexGap sx={{ alignItems: "center" }}>
            <AppLockCard closeAction={closeAction}>
                <Stack
                    component="form"
                    onSubmit={(e: React.SubmitEvent) => void handleSubmit(e)}
                    spacing={0}
                    useFlexGap
                    sx={[{ alignItems: "center" }, appLockModalContentSx]}
                >
                    <AppLockFormHeader
                        title={
                            isReauthentication ? t("password") : t("app_locked")
                        }
                        subtitle={t("app_lock_enter_password")}
                        isReauthentication={isReauthentication}
                        marginBottom={2}
                    />

                    <TextField
                        inputRef={inputRef}
                        fullWidth
                        hiddenLabel
                        variant="standard"
                        autoFocus
                        error={error !== undefined}
                        type={showPassword ? "text" : "password"}
                        value={password}
                        onChange={(e) => {
                            setPassword(e.target.value);
                            setError(undefined);
                        }}
                        disabled={loading}
                        placeholder={
                            isReauthentication
                                ? t("password")
                                : t("app_lock_password")
                        }
                        autoComplete="off"
                        slotProps={{
                            input: {
                                endAdornment: (
                                    <ShowHidePasswordInputAdornment
                                        showPassword={showPassword}
                                        onToggle={() =>
                                            setShowPassword((s) => !s)
                                        }
                                    />
                                ),
                            },
                        }}
                        sx={(theme) => ({
                            ...inputFieldSx(theme),
                            mt: 1,
                            "& .MuiInputAdornment-positionEnd": { pr: 0.5 },
                        })}
                    />

                    <FocusVisibleButton
                        type="submit"
                        fullWidth
                        color="accent"
                        disabled={!password || loading}
                        sx={(theme) => ({
                            ...primaryActionButtonSx(theme),
                            mt: 2,
                        })}
                    >
                        {isReauthentication ? t("authenticate") : t("unlock")}
                    </FocusVisibleButton>
                </Stack>
            </AppLockCard>

            <ErrorMessage
                error={error ?? undefined}
                attemptCount={appLock.invalidAttemptCount}
            />
        </Stack>
    );
};

interface DeviceUnlockContentProps {
    isReauthentication: boolean;
    closeAction?: ReactNode;
}

const DeviceLockUnlockContent = ({
    isReauthentication,
    closeAction,
}: DeviceUnlockContentProps) => {
    const [error, setError] = useState<string>();
    const [loading, setLoading] = useState(true);
    const [showManualUnlockButton, setShowManualUnlockButton] = useState(false);
    const isUnlockInProgress = useRef(false);
    const hasAutoTriggeredUnlock = useRef(false);

    const handleDeviceLockUnlock = useCallback(
        async (source: "auto" | "manual") => {
            if (isUnlockInProgress.current) return;
            isUnlockInProgress.current = true;
            setLoading(true);
            setError(undefined);

            try {
                const result = await attemptDeviceLockUnlock();
                const nextError = deviceLockErrorText(result);
                setError(nextError);
                if (source === "auto" && nextError) {
                    setShowManualUnlockButton(true);
                }
            } catch (e) {
                log.error("Device lock unlock attempt failed", e);
                setError(t("generic_error"));
                if (source === "auto") {
                    setShowManualUnlockButton(true);
                }
            } finally {
                setLoading(false);
                isUnlockInProgress.current = false;
            }
        },
        [],
    );

    useEffect(() => {
        const maybeAutoTriggerUnlock = () => {
            if (hasAutoTriggeredUnlock.current) return;
            if (
                typeof document == "undefined" ||
                document.visibilityState !== "visible" ||
                !document.hasFocus()
            ) {
                return;
            }

            hasAutoTriggeredUnlock.current = true;
            void handleDeviceLockUnlock("auto");
        };

        maybeAutoTriggerUnlock();
        if (hasAutoTriggeredUnlock.current || typeof window == "undefined") {
            return;
        }

        window.addEventListener("focus", maybeAutoTriggerUnlock);
        document.addEventListener("visibilitychange", maybeAutoTriggerUnlock);
        return () => {
            window.removeEventListener("focus", maybeAutoTriggerUnlock);
            document.removeEventListener(
                "visibilitychange",
                maybeAutoTriggerUnlock,
            );
        };
    }, [handleDeviceLockUnlock]);

    return (
        <Stack spacing={0} useFlexGap sx={{ alignItems: "center" }}>
            <AppLockCard closeAction={closeAction}>
                <Stack
                    spacing={0}
                    useFlexGap
                    sx={[{ alignItems: "center" }, appLockModalContentSx]}
                >
                    <AppLockFormHeader
                        title={
                            isReauthentication
                                ? t("authenticate")
                                : t("app_locked")
                        }
                        subtitle={t("device_lock_login_instructions")}
                        isReauthentication={isReauthentication}
                        marginBottom={2}
                    />

                    <FocusVisibleButton
                        fullWidth
                        color="accent"
                        disabled={loading || !showManualUnlockButton}
                        onClick={() => {
                            void handleDeviceLockUnlock("manual");
                        }}
                        sx={(theme) => ({
                            ...primaryActionButtonSx(theme),
                            backgroundColor: ENTE_GREEN,
                            "&:hover": { backgroundColor: ENTE_GREEN_HOVER },
                            fontWeight: 600,
                            mt: 2,
                        })}
                    >
                        {loading ? (
                            <CircularProgress size={18} color="inherit" />
                        ) : isReauthentication ? (
                            t("authenticate")
                        ) : (
                            t("device_lock_login")
                        )}
                    </FocusVisibleButton>
                </Stack>
            </AppLockCard>

            <ErrorMessage error={error} attemptCount={0} />
        </Stack>
    );
};

export const AppLockUnlockForm = ({
    appLock,
    isReauthentication,
    onLogout,
    closeAction,
}: AppLockUnlockFormProps) => {
    const { logout } = useBaseContext();

    if (appLock.lockType === "password") {
        return (
            <PasswordUnlockContent
                appLock={appLock}
                isReauthentication={isReauthentication}
                onLogout={onLogout}
                closeAction={closeAction}
                logout={logout}
            />
        );
    }

    if (appLock.lockType === "device") {
        return (
            <DeviceLockUnlockContent
                isReauthentication={isReauthentication}
                closeAction={closeAction}
            />
        );
    }

    return (
        <PinUnlockContent
            appLock={appLock}
            isReauthentication={isReauthentication}
            onLogout={onLogout}
            closeAction={closeAction}
            logout={logout}
        />
    );
};
