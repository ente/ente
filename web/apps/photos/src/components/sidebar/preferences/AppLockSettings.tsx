import { Stack, TextField, Typography } from "@mui/material";
import { EnteSwitch } from "ente-base/components/EnteSwitch";
import { TitledMiniDialog } from "ente-base/components/MiniDialog";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { ShowHidePasswordInputAdornment } from "ente-base/components/mui/PasswordInputAdornment";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import { errorDialogAttributes } from "ente-base/components/utils/dialog";
import { MenuComponent } from "ente-base/components/v2/MenuComponent";
import { MenuGroupComponent } from "ente-base/components/v2/MenuGroupComponent";
import { RowCard } from "ente-base/components/v2/RowCard";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { useAppLockSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import {
    disableAppLock,
    setAutoLockTime,
    setupDeviceLock,
    setupPassword,
    setupPin,
    shouldShowDeviceLockOption,
    type SetupDeviceLockResult,
} from "ente-new/photos/services/app-lock";
import { t } from "i18next";
import React, { useCallback, useEffect, useRef, useState } from "react";

type DeviceLockEnableOutcome = "success" | "cancelled" | "failed";

export const AppLockSettings: React.FC<
    Pick<NestedSidebarDrawerVisibilityProps, "onRootClose"> & {
        onAuthenticateUser: () => Promise<boolean>;
    }
> = ({ onAuthenticateUser, onRootClose }) => {
    const [open, setOpen] = useState(false);
    const [isAuthenticating, setIsAuthenticating] = useState(false);
    const onClose = () => setOpen(false);
    const state = useAppLockSnapshot();
    const isMacOS =
        typeof navigator != "undefined" &&
        navigator.userAgent.toUpperCase().includes("MAC");

    const [pinDialogOpen, setPinDialogOpen] = useState(false);
    const [passwordDialogOpen, setPasswordDialogOpen] = useState(false);
    const [isSettingDeviceLock, setIsSettingDeviceLock] = useState(false);
    const [showDeviceLockOption, setShowDeviceLockOption] = useState(false);
    const [autoLockOptionsOpen, setAutoLockOptionsOpen] = useState(false);
    const isDeviceLockOptionRequestCancelled = useRef(false);
    const { showMiniDialog } = useBaseContext();

    useEffect(() => {
        if (!state.supported) {
            setShowDeviceLockOption(false);
            return;
        }

        isDeviceLockOptionRequestCancelled.current = false;

        void (async () => {
            try {
                const visible = await shouldShowDeviceLockOption();
                if (!isDeviceLockOptionRequestCancelled.current) {
                    setShowDeviceLockOption(visible);
                }
            } catch (e) {
                log.warn(
                    "Failed to determine device lock option visibility",
                    e,
                );
                if (!isDeviceLockOptionRequestCancelled.current) {
                    setShowDeviceLockOption(false);
                }
            }
        })();

        return () => {
            isDeviceLockOptionRequestCancelled.current = true;
        };
    }, [state.supported]);

    useEffect(() => {
        if (!open) {
            setAutoLockOptionsOpen(false);
        }
    }, [open]);

    const handleRootClose = () => {
        setAutoLockOptionsOpen(false);
        onClose();
        onRootClose();
    };

    const handleSelectDeviceLock =
        useCallback(async (): Promise<DeviceLockEnableOutcome> => {
            if (isSettingDeviceLock) return "failed";

            setIsSettingDeviceLock(true);
            try {
                const result = await setupDeviceLock();
                if (result.status === "success") {
                    return "success";
                }

                if (
                    result.status === "failed" &&
                    result.reason === "native-prompt-failed"
                ) {
                    return "cancelled";
                }

                showMiniDialog(
                    errorDialogAttributes(deviceLockSetupErrorText(result)),
                );
            } catch (e) {
                log.error("Failed to set up device lock app lock", e);
                showMiniDialog(
                    errorDialogAttributes(t("device_lock_setup_failed")),
                );
            } finally {
                setIsSettingDeviceLock(false);
            }

            return "failed";
        }, [isSettingDeviceLock, showMiniDialog]);

    const handleToggleEnabled = useCallback(() => {
        if (!state.supported) return;

        if (state.enabled) {
            showMiniDialog({
                title: t("disable"),
                message: t("app_lock_disable_confirm"),
                continue: {
                    text: t("disable"),
                    color: "critical",
                    action: disableAppLock,
                },
            });
            return;
        }

        void (async () => {
            if (isMacOS) {
                const outcome = await handleSelectDeviceLock();
                if (outcome !== "failed") return;
            }

            setPinDialogOpen(true);
        })();
    }, [
        state.enabled,
        state.supported,
        showMiniDialog,
        isMacOS,
        handleSelectDeviceLock,
    ]);

    const handleSelectPin = useCallback(() => {
        setPinDialogOpen(true);
    }, []);

    const handleSelectPassword = useCallback(() => {
        setPasswordDialogOpen(true);
    }, []);

    const handlePinSetupComplete = useCallback(() => {
        setPinDialogOpen(false);
    }, []);

    const handlePasswordSetupComplete = useCallback(() => {
        setPasswordDialogOpen(false);
    }, []);

    const authenticateAndRun = async (action: () => void) => {
        if (isAuthenticating) return;
        setIsAuthenticating(true);
        try {
            if (await onAuthenticateUser()) action();
        } catch (error) {
            log.error("Failed to authenticate app lock settings", error);
        } finally {
            setIsAuthenticating(false);
        }
    };

    return (
        <>
            <RowCard
                title={t("app_lock")}
                subtitle={
                    !state.supported ? t("app_lock_not_supported") : undefined
                }
                endIcon={
                    <EnteSwitch
                        checked={state.enabled}
                        disabled={
                            !state.supported ||
                            isAuthenticating ||
                            isSettingDeviceLock
                        }
                        onChange={() =>
                            void authenticateAndRun(handleToggleEnabled)
                        }
                        slotProps={{ input: { "aria-label": t("app_lock") } }}
                    />
                }
            />
            {state.enabled && (
                <Stack sx={{ pl: 2 }}>
                    <RowCard
                        title="App lock options"
                        onClick={() =>
                            void authenticateAndRun(() => setOpen(true))
                        }
                    />
                </Stack>
            )}
            <TitledNestedSidebarDrawer
                maxWidth="440px"
                {...{ open, onClose }}
                onRootClose={handleRootClose}
                title={t("app_lock")}
            >
                <Stack sx={{ px: 2, py: 1, gap: 1 }}>
                    {state.enabled && (
                        <>
                            <Stack>
                                <Typography
                                    variant="small"
                                    sx={{
                                        px: 1,
                                        pb: "6px",
                                        color: "text.muted",
                                    }}
                                >
                                    {t("lock_type")}
                                </Typography>
                                <MenuGroupComponent>
                                    <MenuComponent
                                        title={t("PIN")}
                                        selected={state.lockType === "pin"}
                                        onClick={handleSelectPin}
                                    />
                                    <MenuComponent
                                        title={t("app_lock_password")}
                                        selected={state.lockType === "password"}
                                        onClick={handleSelectPassword}
                                    />
                                    {showDeviceLockOption && (
                                        <MenuComponent
                                            title={t("device_lock")}
                                            selected={
                                                state.lockType === "device"
                                            }
                                            loading={isSettingDeviceLock}
                                            onClick={() =>
                                                void handleSelectDeviceLock()
                                            }
                                        />
                                    )}
                                </MenuGroupComponent>
                            </Stack>

                            <RowCard
                                title={t("auto_lock")}
                                subtitle={autoLockLabel(state.autoLockTimeMs)}
                                onClick={() => setAutoLockOptionsOpen(true)}
                            />
                        </>
                    )}
                </Stack>
                <AutoLockOptionsDrawer
                    open={autoLockOptionsOpen}
                    onClose={() => setAutoLockOptionsOpen(false)}
                    onRootClose={handleRootClose}
                    currentValue={state.autoLockTimeMs}
                />
            </TitledNestedSidebarDrawer>

            <PinSetupDialog
                open={pinDialogOpen}
                onClose={() => setPinDialogOpen(false)}
                onComplete={handlePinSetupComplete}
            />
            <PasswordSetupDialog
                open={passwordDialogOpen}
                onClose={() => setPasswordDialogOpen(false)}
                onComplete={handlePasswordSetupComplete}
            />
        </>
    );
};

const deviceLockSetupErrorText = (result: SetupDeviceLockResult): string => {
    if (result.status === "success") return "";

    if (result.status === "not-supported") {
        switch (result.reason) {
            case "touchid-temporarily-unavailable":
            case "touchid-api-error":
                return t("device_lock_setup_failed");
            case "unsupported-platform":
            case "touchid-not-enrolled":
                return t("device_lock_not_supported");
        }
    }

    if (result.reason === "native-prompt-failed") {
        return t("device_lock_setup_cancelled");
    }

    return t("device_lock_setup_failed");
};

const autoLockOptions: { labelKey: string; ms: number }[] = [
    { labelKey: "auto_lock_immediately", ms: 0 },
    { labelKey: "auto_lock_5_seconds", ms: 5_000 },
    { labelKey: "auto_lock_15_seconds", ms: 15_000 },
    { labelKey: "auto_lock_1_minute", ms: 60_000 },
    { labelKey: "auto_lock_5_minutes", ms: 300_000 },
    { labelKey: "auto_lock_30_minutes", ms: 1_800_000 },
];

const autoLockLabel = (ms: number): string => {
    const option = autoLockOptions.find((o) => o.ms === ms);
    return t(option?.labelKey ?? "auto_lock_immediately");
};

interface SetupDialogProps {
    open: boolean;
    onClose: () => void;
    onComplete: () => void;
}

const PinSetupDialog: React.FC<SetupDialogProps> = ({
    open,
    onClose,
    onComplete,
}) => {
    const [step, setStep] = useState<"enter" | "confirm">("enter");
    const [pin, setPin] = useState(["", "", "", ""]);
    const [confirmPin, setConfirmPin] = useState(["", "", "", ""]);
    const [error, setError] = useState("");

    const inputRefs = useRef<(HTMLInputElement | null)[]>([]);
    const confirmInputRefs = useRef<(HTMLInputElement | null)[]>([]);
    const focusTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

    // Step changes remount the inputs, so focus must wait for the next render.
    const queueFocus = useCallback((fn: () => void, delay: number) => {
        if (focusTimerRef.current) {
            clearTimeout(focusTimerRef.current);
        }
        focusTimerRef.current = setTimeout(fn, delay);
    }, []);

    useEffect(() => {
        return () => {
            if (focusTimerRef.current) {
                clearTimeout(focusTimerRef.current);
                focusTimerRef.current = null;
            }
        };
    }, []);

    useEffect(() => {
        if (!open) return;

        queueFocus(
            () =>
                (step === "enter"
                    ? inputRefs
                    : confirmInputRefs
                ).current[0]?.focus(),
            50,
        );
    }, [open, step, queueFocus]);

    const resetState = useCallback(() => {
        setStep("enter");
        setPin(["", "", "", ""]);
        setConfirmPin(["", "", "", ""]);
        setError("");
    }, []);

    const handleClose = useCallback(() => {
        resetState();
        onClose();
    }, [resetState, onClose]);

    const handlePinDigitChange = (
        index: number,
        value: string,
        isConfirm: boolean,
    ) => {
        const digit = value.replace(/\D/g, "").slice(-1);

        if (isConfirm) {
            const next = [...confirmPin];
            next[index] = digit;
            setConfirmPin(next);

            if (digit && index < 3) {
                confirmInputRefs.current[index + 1]?.focus();
            }
        } else {
            const next = [...pin];
            next[index] = digit;
            setPin(next);
            if (digit && index < 3) {
                inputRefs.current[index + 1]?.focus();
            }
        }
        setError("");
    };

    const handlePinKeyDown = (
        index: number,
        e: React.KeyboardEvent,
        isConfirm: boolean,
    ) => {
        if (e.key === "Backspace") {
            const current = isConfirm ? confirmPin : pin;
            if (!current[index] && index > 0) {
                const refs = isConfirm ? confirmInputRefs : inputRefs;
                refs.current[index - 1]?.focus();
            }
        }
    };

    const handleNext = useCallback(() => {
        if (pin.some((d) => !d)) return;
        setStep("confirm");
    }, [pin]);

    const handleBack = useCallback(() => {
        setStep("enter");
        setConfirmPin(["", "", "", ""]);
        setError("");
    }, []);

    const handleConfirm = useCallback(async () => {
        if (confirmPin.some((d) => !d)) return;

        const pinStr = pin.join("");
        const confirmStr = confirmPin.join("");
        if (pinStr !== confirmStr) {
            setError(t("pin_mismatch"));
            setConfirmPin(["", "", "", ""]);
            queueFocus(() => confirmInputRefs.current[0]?.focus(), 50);
            return;
        }
        try {
            await setupPin(pinStr);
            onComplete();
            resetState();
        } catch (e) {
            log.error("Failed to set up PIN app lock", e);
            setError(t("generic_error"));
            setConfirmPin(["", "", "", ""]);
            queueFocus(() => confirmInputRefs.current[0]?.focus(), 50);
        }
    }, [pin, confirmPin, onComplete, queueFocus, resetState]);

    const handleSubmit = useCallback(
        (e: React.SubmitEvent) => {
            e.preventDefault();
            if (step === "enter") {
                handleNext();
                return;
            }
            void handleConfirm();
        },
        [step, handleNext, handleConfirm],
    );

    const renderPinInputs = (
        values: string[],
        refs: React.RefObject<(HTMLInputElement | null)[]>,
        isConfirm: boolean,
        hasError?: boolean,
    ) => (
        <Stack
            direction="row"
            sx={{ gap: 1.5, width: "100%", justifyContent: "space-between" }}
        >
            {values.map((digit, i) => (
                <TextField
                    key={i}
                    hiddenLabel
                    error={hasError}
                    value={digit}
                    onChange={(e) =>
                        handlePinDigitChange(i, e.target.value, isConfirm)
                    }
                    onKeyDown={(e) => handlePinKeyDown(i, e, isConfirm)}
                    inputRef={(el: HTMLInputElement | null) => {
                        refs.current[i] = el;
                    }}
                    type="password"
                    slotProps={{
                        htmlInput: {
                            maxLength: 1,
                            inputMode: "numeric",
                            autoComplete: "off",
                            style: {
                                textAlign: "center",
                                fontSize: "1.25rem",
                                padding: "12px 0",
                            },
                            "aria-label": `PIN digit ${String(i + 1)}`,
                        },
                    }}
                    sx={{ flex: 1, minWidth: 0 }}
                />
            ))}
        </Stack>
    );

    return (
        <TitledMiniDialog
            open={open}
            onClose={handleClose}
            title={t("app_lock_set_pin")}
            sx={{
                "& .MuiDialogTitle-root": { pb: 0 },
                "& .MuiDialogTitle-root + .MuiDialogContent-root": { pt: 0 },
            }}
        >
            <Stack
                component="form"
                onSubmit={(e: React.SubmitEvent) => handleSubmit(e)}
                sx={{ gap: 1.5, py: 0 }}
            >
                {step === "enter" ? (
                    <>
                        <Typography
                            sx={{ color: "text.muted", textAlign: "left" }}
                        >
                            {t("enter_pin")}
                        </Typography>
                        {renderPinInputs(pin, inputRefs, false)}
                        <FocusVisibleButton
                            fullWidth
                            color="accent"
                            type="submit"
                            disabled={pin.some((d) => !d)}
                        >
                            {t("next")}
                        </FocusVisibleButton>
                    </>
                ) : (
                    <>
                        <Typography
                            sx={{ color: "text.muted", textAlign: "left" }}
                        >
                            {t("confirm_pin")}
                        </Typography>
                        {renderPinInputs(
                            confirmPin,
                            confirmInputRefs,
                            true,
                            !!error,
                        )}
                        {error && (
                            <Typography
                                variant="small"
                                sx={{
                                    color: "critical.main",
                                    textAlign: "left",
                                }}
                            >
                                {error}
                            </Typography>
                        )}
                        <Stack sx={{ gap: 1.5, width: "100%" }}>
                            <FocusVisibleButton
                                fullWidth
                                color="accent"
                                type="submit"
                                disabled={confirmPin.some((d) => !d)}
                            >
                                {t("confirm")}
                            </FocusVisibleButton>
                            <FocusVisibleButton
                                fullWidth
                                color="secondary"
                                type="button"
                                onClick={handleBack}
                            >
                                {t("go_back")}
                            </FocusVisibleButton>
                        </Stack>
                    </>
                )}
            </Stack>
        </TitledMiniDialog>
    );
};

const PasswordSetupDialog: React.FC<SetupDialogProps> = ({
    open,
    onClose,
    onComplete,
}) => {
    const [step, setStep] = useState<"enter" | "confirm">("enter");
    const [password, setPassword] = useState("");
    const [confirmPassword, setConfirmPassword] = useState("");
    const [showPassword, setShowPassword] = useState(false);
    const [showConfirmPassword, setShowConfirmPassword] = useState(false);
    const [error, setError] = useState("");

    const passwordInputRef = useRef<HTMLInputElement>(null);
    const confirmPasswordInputRef = useRef<HTMLInputElement>(null);
    const focusTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

    const queueFocus = useCallback((fn: () => void, delay: number) => {
        if (focusTimerRef.current) {
            clearTimeout(focusTimerRef.current);
        }
        focusTimerRef.current = setTimeout(fn, delay);
    }, []);

    useEffect(() => {
        return () => {
            if (focusTimerRef.current) {
                clearTimeout(focusTimerRef.current);
                focusTimerRef.current = null;
            }
        };
    }, []);

    useEffect(() => {
        if (!open) return;

        queueFocus(
            () =>
                (step === "enter"
                    ? passwordInputRef.current
                    : confirmPasswordInputRef.current
                )?.focus(),
            50,
        );
    }, [open, step, queueFocus]);

    const resetState = useCallback(() => {
        setStep("enter");
        setPassword("");
        setConfirmPassword("");
        setShowPassword(false);
        setShowConfirmPassword(false);
        setError("");
    }, []);

    const handleClose = useCallback(() => {
        resetState();
        onClose();
    }, [resetState, onClose]);

    const handleNext = useCallback(() => {
        if (!password) return;
        setStep("confirm");
    }, [password]);

    const handleBack = useCallback(() => {
        setStep("enter");
        setConfirmPassword("");
        setError("");
    }, []);

    const handleConfirm = useCallback(async () => {
        if (password !== confirmPassword) {
            setError(t("app_lock_password_mismatch"));
            setConfirmPassword("");
            queueFocus(() => confirmPasswordInputRef.current?.focus(), 50);
            return;
        }
        try {
            await setupPassword(password);
            onComplete();
            resetState();
        } catch (e) {
            log.error("Failed to set up password app lock", e);
            setError(t("generic_error"));
            setConfirmPassword("");
            queueFocus(() => confirmPasswordInputRef.current?.focus(), 50);
        }
    }, [password, confirmPassword, onComplete, queueFocus, resetState]);

    const handleSubmit = useCallback(
        (e: React.SubmitEvent) => {
            e.preventDefault();
            if (step === "enter") {
                handleNext();
                return;
            }
            void handleConfirm();
        },
        [step, handleNext, handleConfirm],
    );

    return (
        <TitledMiniDialog
            open={open}
            onClose={handleClose}
            title={t("app_lock_set_password")}
            sx={{
                "& .MuiDialogTitle-root": { pb: 0 },
                "& .MuiDialogTitle-root + .MuiDialogContent-root": { pt: 0 },
            }}
        >
            <Stack
                component="form"
                onSubmit={(e: React.SubmitEvent) => handleSubmit(e)}
                sx={{ gap: 2, py: 1 }}
            >
                {step === "enter" ? (
                    <>
                        <TextField
                            fullWidth
                            inputRef={passwordInputRef}
                            label={t("app_lock_enter_password")}
                            type={showPassword ? "text" : "password"}
                            value={password}
                            onChange={(e) => {
                                setPassword(e.target.value);
                                setError("");
                            }}
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
                        />
                        <FocusVisibleButton
                            fullWidth
                            color="accent"
                            type="submit"
                            disabled={!password}
                        >
                            {t("next")}
                        </FocusVisibleButton>
                    </>
                ) : (
                    <>
                        <TextField
                            fullWidth
                            inputRef={confirmPasswordInputRef}
                            label={t("app_lock_confirm_password")}
                            type={showConfirmPassword ? "text" : "password"}
                            value={confirmPassword}
                            error={!!error}
                            helperText={error || undefined}
                            onChange={(e) => {
                                setConfirmPassword(e.target.value);
                                setError("");
                            }}
                            slotProps={{
                                input: {
                                    endAdornment: (
                                        <ShowHidePasswordInputAdornment
                                            showPassword={showConfirmPassword}
                                            onToggle={() =>
                                                setShowConfirmPassword(
                                                    (s) => !s,
                                                )
                                            }
                                        />
                                    ),
                                },
                            }}
                        />
                        <Stack sx={{ gap: 1.5, width: "100%" }}>
                            <FocusVisibleButton
                                fullWidth
                                color="accent"
                                type="submit"
                                disabled={!confirmPassword}
                            >
                                {t("confirm")}
                            </FocusVisibleButton>
                            <FocusVisibleButton
                                fullWidth
                                color="secondary"
                                type="button"
                                onClick={handleBack}
                            >
                                {t("go_back")}
                            </FocusVisibleButton>
                        </Stack>
                    </>
                )}
            </Stack>
        </TitledMiniDialog>
    );
};

interface AutoLockOptionsDrawerProps extends NestedSidebarDrawerVisibilityProps {
    currentValue: number;
}

const AutoLockOptionsDrawer: React.FC<AutoLockOptionsDrawerProps> = ({
    open,
    onClose,
    onRootClose,
    currentValue,
}) => {
    const [pendingAutoLockMs, setPendingAutoLockMs] = useState<number | null>(
        null,
    );

    const selectedMs = autoLockOptions.some((o) => o.ms === currentValue)
        ? currentValue
        : autoLockOptions[0]!.ms;

    const setAutoLockTimeValue = useCallback(
        (ms: number) => {
            if (pendingAutoLockMs !== null || ms === currentValue) return;

            setPendingAutoLockMs(ms);
            void (async () => {
                try {
                    await setAutoLockTime(ms);
                    onClose();
                } catch (e) {
                    log.error("Failed to update app lock auto-lock time", e);
                } finally {
                    setPendingAutoLockMs((pending) =>
                        pending === ms ? null : pending,
                    );
                }
            })();
        },
        [pendingAutoLockMs, currentValue, onClose],
    );

    return (
        <TitledNestedSidebarDrawer
            maxWidth="440px"
            anchor="left"
            {...{ open, onClose }}
            onRootClose={onRootClose}
            title={t("auto_lock")}
        >
            <Stack sx={{ px: 2, py: 1 }}>
                <MenuGroupComponent>
                    {autoLockOptions.map((option) => (
                        <MenuComponent
                            key={option.ms}
                            title={t(option.labelKey)}
                            disabled={pendingAutoLockMs !== null}
                            loading={pendingAutoLockMs === option.ms}
                            selected={selectedMs === option.ms}
                            onClick={() => setAutoLockTimeValue(option.ms)}
                        />
                    ))}
                </MenuGroupComponent>
            </Stack>
        </TitledNestedSidebarDrawer>
    );
};
