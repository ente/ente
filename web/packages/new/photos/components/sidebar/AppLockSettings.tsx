import CheckIcon from "@mui/icons-material/Check";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import { Stack, TextField, Typography } from "@mui/material";
import { TitledMiniDialog } from "ente-base/components/MiniDialog";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { ShowHidePasswordInputAdornment } from "ente-base/components/mui/PasswordInputAdornment";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import {
    RowButton,
    RowButtonDivider,
    RowButtonEndActivityIndicator,
    RowButtonGroup,
    RowSwitch,
} from "ente-base/components/RowButton";
import { errorDialogAttributes } from "ente-base/components/utils/dialog";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { t } from "i18next";
import React, { useCallback, useEffect, useRef, useState } from "react";
import {
    disableAppLock,
    setAutoLockTime,
    setupDeviceLock,
    setupPassword,
    setupPin,
    shouldShowDeviceLockOption,
    type SetupDeviceLockResult,
} from "../../services/app-lock";
import { useAppLockSnapshot } from "../utils/use-snapshot";

type DeviceLockEnableOutcome = "success" | "cancelled" | "failed";

export const AppLockSettings: React.FC<NestedSidebarDrawerVisibilityProps> = ({
    open,
    onClose,
    onRootClose,
}) => {
    const state = useAppLockSnapshot();
    const isMacOS =
        typeof navigator != "undefined" &&
        navigator.userAgent.toUpperCase().includes("MAC");

    // For the 4-digit PIN setup and confirmation dialog.
    const [pinDialogOpen, setPinDialogOpen] = useState(false);
    // For the password setup and confirmation dialog.
    const [passwordDialogOpen, setPasswordDialogOpen] = useState(false);
    // Loading/disable flag while async device-lock setup is running.
    const [isSettingDeviceLock, setIsSettingDeviceLock] = useState(false);
    // Controls whether the Device lock option should be shown after a compatibility check.
    const [showDeviceLockOption, setShowDeviceLockOption] = useState(false);
    // For the auto-lock duration selection nested drawer.
    const [autoLockOptionsOpen, setAutoLockOptionsOpen] = useState(false);
    // Cancel flag used to avoid state updates after unmount.
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

    /**
     * Close both levels of the nested drawer.
     */
    const handleRootClose = () => {
        setAutoLockOptionsOpen(false);
        onClose();
        onRootClose();
    };

    const handleSelectDeviceLock =
        useCallback(async (): Promise<DeviceLockEnableOutcome> => {
            // Ignore repeated clicks while setup is already running.
            if (isSettingDeviceLock) return "failed";

            // Show loading state while native device-lock setup runs.
            setIsSettingDeviceLock(true);
            try {
                // setupDeviceLock performs capability checks and returns typed
                // failure reasons when setup is unavailable or not completed.
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

            // Fallback when macOS device lock setup is unavailable/failed.
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

    // Close the PIN setup dialog after a successful setup.
    const handlePinSetupComplete = useCallback(() => {
        setPinDialogOpen(false);
    }, []);

    // Close the password setup dialog after a successful setup.
    const handlePasswordSetupComplete = useCallback(() => {
        setPasswordDialogOpen(false);
    }, []);

    return (
        <>
            <TitledNestedSidebarDrawer
                {...{ open, onClose }}
                onRootClose={handleRootClose}
                title={t("app_lock")}
            >
                <Stack sx={{ px: "16px", py: "20px", gap: "24px" }}>
                    <RowButtonGroup>
                        <RowSwitch
                            label={t("enabled")}
                            checked={state.enabled}
                            onClick={handleToggleEnabled}
                        />
                    </RowButtonGroup>

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
                                <RowButtonGroup>
                                    <RowButton
                                        label={t("PIN")}
                                        endIcon={
                                            state.lockType === "pin" ? (
                                                <CheckIcon
                                                    sx={{
                                                        color: "accent.main",
                                                    }}
                                                />
                                            ) : undefined
                                        }
                                        onClick={handleSelectPin}
                                    />
                                    <RowButtonDivider />
                                    <RowButton
                                        label={t("app_lock_password")}
                                        endIcon={
                                            state.lockType === "password" ? (
                                                <CheckIcon
                                                    sx={{
                                                        color: "accent.main",
                                                    }}
                                                />
                                            ) : undefined
                                        }
                                        onClick={handleSelectPassword}
                                    />
                                    {showDeviceLockOption && (
                                        <>
                                            <RowButtonDivider />
                                            <RowButton
                                                label={t("device_lock")}
                                                caption={
                                                    isSettingDeviceLock
                                                        ? t("loading")
                                                        : undefined
                                                }
                                                disabled={isSettingDeviceLock}
                                                endIcon={
                                                    state.lockType ===
                                                    "device" ? (
                                                        <CheckIcon
                                                            sx={{
                                                                color: "accent.main",
                                                            }}
                                                        />
                                                    ) : undefined
                                                }
                                                onClick={() =>
                                                    void handleSelectDeviceLock()
                                                }
                                            />
                                        </>
                                    )}
                                </RowButtonGroup>
                            </Stack>

                            <Stack>
                                <RowButtonGroup>
                                    <RowButton
                                        label={t("auto_lock")}
                                        endIcon={<ChevronRightIcon />}
                                        caption={autoLockLabel(
                                            state.autoLockTimeMs,
                                        )}
                                        onClick={() =>
                                            setAutoLockOptionsOpen(true)
                                        }
                                    />
                                </RowButtonGroup>
                            </Stack>
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

// -- Auto-lock duration helpers --

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

// -- PIN Setup Dialog --

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
    // For PIN setup, there are two modals: one for initial input and one for confirmation.
    const [step, setStep] = useState<"enter" | "confirm">("enter");
    // Stores the 4 PIN digits entered by the user
    const [pin, setPin] = useState(["", "", "", ""]);
    // Stores the 4 PIN digits entered for confirmation
    const [confirmPin, setConfirmPin] = useState(["", "", "", ""]);
    // Stores error message if PIN confirmation fails
    const [error, setError] = useState("");

    // DOM refs for the 4 PIN inputs in the "enter PIN" step.
    // We keep these refs so the component can imperatively move focus between
    // single-character fields (auto-advance on digit entry, move back on
    // Backspace, and return focus to the first field when switching steps).
    const inputRefs = useRef<(HTMLInputElement | null)[]>([]);
    // DOM refs for the 4 PIN inputs in the "confirm PIN" step.
    const confirmInputRefs = useRef<(HTMLInputElement | null)[]>([]);
    // Tracks pending delayed focus so we can cancel stale timers safely.
    const focusTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

    /**
     * queueFocus clears any existing timer and schedules a new focus callback
     * with setTimeout(fn, delay).
     *
     * When steps change, inputs are remounted, so an immediate .focus() can
     * run too early. This helper waits briefly, then focuses the correct field.
     */
    const queueFocus = useCallback((fn: () => void, delay: number) => {
        if (focusTimerRef.current) {
            clearTimeout(focusTimerRef.current);
        }
        focusTimerRef.current = setTimeout(fn, delay);
    }, []);

    // Cleanup function to clear the focusTimer when the component unmounts.
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

    // Sanitize input, write a digit, move focus forward, and reset the error.
    const handlePinDigitChange = (
        index: number,
        value: string,
        isConfirm: boolean,
    ) => {
        // Removes every non-digit character and keeps only the last digit.
        const digit = value.replace(/\D/g, "").slice(-1);

        /**
         * If the confirmation step is active, update the confirmPin state;
         * otherwise, update the pin state.
         */

        if (isConfirm) {
            const next = [...confirmPin];
            next[index] = digit;
            setConfirmPin(next);

            // If it's not the last index, advance focus automatically.
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

    /**
     * Invoked on keypress. If the key is Backspace, use the active PIN array
     * and, when the current box is empty and not the first one, move focus to
     * the previous input.
     */
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

    /**
     * Invoked when the next button is pressed on the first step,
     * checks if all digits are present, and proceeds to the confirm step.
     */
    const handleNext = useCallback(() => {
        if (pin.some((d) => !d)) return;
        setStep("confirm");
    }, [pin]);

    /**
     * If Back is pressed in the confirmation step, reset the
     * confirmation array and switch to the entry step.
     */
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

// -- Password Setup Dialog --

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

// -- Auto-lock nested drawer --

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
            anchor="left"
            {...{ open, onClose }}
            onRootClose={onRootClose}
            title={t("auto_lock")}
        >
            <Stack sx={{ py: "20px", px: "8px" }}>
                <RowButtonGroup>
                    {autoLockOptions.map((option, index) => (
                        <React.Fragment key={option.ms}>
                            <RowButton
                                label={t(option.labelKey)}
                                disabled={pendingAutoLockMs !== null}
                                endIcon={
                                    pendingAutoLockMs === option.ms ? (
                                        <RowButtonEndActivityIndicator />
                                    ) : selectedMs === option.ms ? (
                                        <CheckIcon
                                            sx={{ color: "accent.main" }}
                                        />
                                    ) : undefined
                                }
                                onClick={() => setAutoLockTimeValue(option.ms)}
                            />
                            {index != autoLockOptions.length - 1 && (
                                <RowButtonDivider />
                            )}
                        </React.Fragment>
                    ))}
                </RowButtonGroup>
            </Stack>
        </TitledNestedSidebarDrawer>
    );
};
