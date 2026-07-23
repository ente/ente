import AccessTimeRoundedIcon from "@mui/icons-material/AccessTimeRounded";
import CheckCircleRoundedIcon from "@mui/icons-material/CheckCircleRounded";
import CloudUploadOutlinedIcon from "@mui/icons-material/CloudUploadOutlined";
import ErrorOutlineRoundedIcon from "@mui/icons-material/ErrorOutlineRounded";
import LockResetRoundedIcon from "@mui/icons-material/LockResetRounded";
import type { SxProps, Theme } from "@mui/material";
import {
    Alert,
    Box,
    Button,
    CircularProgress,
    Stack,
    TextField,
    Typography,
} from "@mui/material";
import { isWeakPassword } from "ente-accounts-rs/utils/password";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { ShowHidePasswordInputAdornment } from "ente-base/components/mui/PasswordInputAdornment";
import log from "ente-base/log";
import type { LegacyKitRecoveryHandle } from "ente-wasm";
import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
    changeLegacyKitPassword,
    openLegacyKitRecovery,
    refreshLegacyKitRecoverySession,
    type LegacyKitRecoverySession,
} from "../features/legacy-kit/recovery";
import { readLegacyKitCodeFromFile } from "../features/legacy-kit/scan";
import {
    parseLegacyKitShare,
    validateLegacyKitSharePair,
    type LegacyKitShare,
} from "../features/legacy-kit/share";

type SlotID = "first" | "second";

interface SheetSlot {
    error?: string;
    fileName?: string;
    isReading: boolean;
    rawCode: string;
    share?: LegacyKitShare;
}

const emptySlot = (): SheetSlot => ({ isReading: false, rawCode: "" });

const slotLabels: Record<SlotID, string> = {
    first: "Sheet 1 of 2",
    second: "Sheet 2 of 2",
};

const slotNumbers: Record<SlotID, number> = { first: 1, second: 2 };

const inactiveLegacyKitRequestPaths = [
    "/legacy-kits/recovery/challenge",
    "/legacy-kits/recovery/open",
];

const getErrorMessage = (error: unknown) =>
    error instanceof Error
        ? error.message
        : typeof error === "object" && error && "message" in error
          ? String(error.message)
          : "Something went wrong.";

const isInactiveLegacyKitError = (error: unknown) => {
    const message = getErrorMessage(error).toLowerCase();
    return (
        message.includes("legacy kit not found") ||
        (message.includes("http 404") &&
            inactiveLegacyKitRequestPaths.some((path) =>
                message.includes(path),
            ))
    );
};

const parseSlotCode = (rawCode: string): Pick<SheetSlot, "error" | "share"> => {
    if (!rawCode.trim()) {
        return {};
    }

    try {
        return { share: parseLegacyKitShare(rawCode) };
    } catch {
        return { error: "Invalid sheet." };
    }
};

const displayWaitTarget = (waitRemainingMicros: number) => {
    if (waitRemainingMicros <= 0) {
        return "now";
    }

    const target = new Date(Date.now() + waitRemainingMicros / 1000);
    return new Intl.DateTimeFormat(undefined, {
        day: "numeric",
        hour: "numeric",
        minute: "2-digit",
        month: "long",
        year: "numeric",
    }).format(target);
};

const textFieldSx: SxProps<Theme> = {
    m: 0,
    "& .MuiFilledInput-root": {
        backgroundColor: "background.paper",
        border: "1px solid",
        borderColor: "transparent",
        borderRadius: "16px",
        minHeight: "52px",
        overflow: "hidden",
        transition: "border-color 160ms ease, background-color 160ms ease",
        "&:hover": {
            backgroundColor: "background.paper",
            borderColor: "stroke.fainter",
        },
        "&.Mui-focused": {
            backgroundColor: "background.paper",
            borderColor: "accent.main",
        },
        "&.Mui-disabled": { backgroundColor: "fill.fainter" },
    },
    "& .MuiFilledInput-input": {
        color: "text.base",
        fontSize: 14,
        fontWeight: 500,
        lineHeight: "20px",
        px: 2,
        py: "15px",
    },
    "& .MuiInputBase-multiline > .MuiInputBase-input": { py: 0 },
    "& .MuiFormHelperText-root": { mx: 0, mt: 0.75 },
};

const buttonSx = {
    borderRadius: "20px",
    fontSize: 14,
    fontWeight: 600,
    height: 52,
    lineHeight: "20px",
};

const Page: React.FC = () => {
    const [hasStarted, setHasStarted] = useState(false);
    const [slots, setSlots] = useState<Record<SlotID, SheetSlot>>({
        first: emptySlot(),
        second: emptySlot(),
    });
    const [handle, setHandle] = useState<LegacyKitRecoveryHandle>();
    const [session, setSession] = useState<LegacyKitRecoverySession>();
    const [isOpening, setIsOpening] = useState(false);
    const [isRefreshing, setIsRefreshing] = useState(false);
    const [isKitInactive, setIsKitInactive] = useState(false);
    const [openError, setOpenError] = useState<string>();

    const shares = useMemo<[LegacyKitShare, LegacyKitShare] | undefined>(() => {
        const firstShare = slots.first.share;
        const secondShare = slots.second.share;
        return firstShare && secondShare
            ? [firstShare, secondShare]
            : undefined;
    }, [slots.first.share, slots.second.share]);

    const pairError = useMemo(() => {
        if (!shares) {
            return undefined;
        }
        try {
            validateLegacyKitSharePair(shares[0], shares[1]);
            return undefined;
        } catch (error) {
            return getErrorMessage(error);
        }
    }, [shares]);

    const canOpen = !!shares && !pairError && !isOpening;

    const updateSlot = useCallback(
        (slotID: SlotID, patch: Partial<SheetSlot>) => {
            setSlots((current) => ({
                ...current,
                [slotID]: { ...current[slotID], ...patch },
            }));
        },
        [],
    );

    const handleCodeChange = useCallback(
        (slotID: SlotID, rawCode: string) => {
            const parsed = parseSlotCode(rawCode);
            setOpenError(undefined);
            updateSlot(slotID, {
                error: parsed.error,
                rawCode,
                fileName: undefined,
                share: parsed.share,
            });
        },
        [updateSlot],
    );

    const handleFile = useCallback(
        (slotID: SlotID, file: File | undefined) => {
            if (!file) {
                return;
            }

            setOpenError(undefined);
            updateSlot(slotID, {
                error: undefined,
                fileName: file.name,
                isReading: true,
                rawCode: "",
                share: undefined,
            });

            void readLegacyKitCodeFromFile(file)
                .then((rawCode) => {
                    const parsed = parseSlotCode(rawCode);
                    updateSlot(slotID, {
                        error: parsed.error,
                        fileName: file.name,
                        isReading: false,
                        rawCode,
                        share: parsed.share,
                    });
                })
                .catch((error: unknown) => {
                    log.error("Could not read legacy kit sheet", error);
                    updateSlot(slotID, {
                        error: getErrorMessage(error),
                        isReading: false,
                        rawCode: "",
                        share: undefined,
                    });
                });
        },
        [updateSlot],
    );

    const openRecovery = useCallback(async () => {
        if (!shares || pairError) {
            return;
        }

        setIsOpening(true);
        setOpenError(undefined);

        try {
            const opened = await openLegacyKitRecovery(shares);
            setHandle(opened.handle);
            setSession(opened.session);
        } catch (error) {
            log.error("Legacy kit recovery open failed", error);
            if (isInactiveLegacyKitError(error)) {
                setIsKitInactive(true);
                return;
            }
            setOpenError(getErrorMessage(error));
        } finally {
            setIsOpening(false);
        }
    }, [pairError, shares]);

    const refreshSession = useCallback(async () => {
        if (!handle) {
            return;
        }
        setIsRefreshing(true);
        setOpenError(undefined);
        try {
            setSession(await refreshLegacyKitRecoverySession(handle));
        } catch (error) {
            log.error("Legacy kit recovery refresh failed", error);
            if (isInactiveLegacyKitError(error)) {
                setIsKitInactive(true);
                return;
            }
            setOpenError(getErrorMessage(error));
        } finally {
            setIsRefreshing(false);
        }
    }, [handle]);

    useEffect(() => {
        if (!handle || session?.status !== "WAITING") {
            return;
        }
        const timer = setInterval(() => void refreshSession(), 30_000);
        return () => clearInterval(timer);
    }, [handle, refreshSession, session?.status]);

    const handlePasswordSubmit = useCallback(
        async (
            password: string,
            setPasswordsFieldError: (message: string) => void,
        ) => {
            if (!handle) {
                setPasswordsFieldError("Recovery session is not open.");
                return;
            }
            try {
                await changeLegacyKitPassword(handle, password);
                setSession((current) =>
                    current ? { ...current, status: "RECOVERED" } : current,
                );
            } catch (error) {
                log.error("Legacy kit password change failed", error);
                if (isInactiveLegacyKitError(error)) {
                    setIsKitInactive(true);
                    return;
                }
                setPasswordsFieldError(getErrorMessage(error));
            }
        },
        [handle],
    );

    return (
        <LegacyShell>
            {!hasStarted ? (
                <LandingStep
                    onStart={() => {
                        setIsKitInactive(false);
                        setHasStarted(true);
                    }}
                />
            ) : isKitInactive ? (
                <InactiveLegacyKitStep />
            ) : !session ? (
                <UploadStep
                    slots={slots}
                    pairError={pairError}
                    openError={openError}
                    isOpening={isOpening}
                    canOpen={canOpen}
                    onFile={handleFile}
                    onText={handleCodeChange}
                    onOpen={() => void openRecovery()}
                />
            ) : session.status === "WAITING" ? (
                <WaitingStep
                    session={session}
                    isRefreshing={isRefreshing}
                    openError={openError}
                />
            ) : session.status === "READY" ? (
                <ResetPasswordStep onSubmit={handlePasswordSubmit} />
            ) : (
                <TerminalStatusStep session={session} />
            )}
        </LegacyShell>
    );
};

interface LegacyShellProps {
    children: React.ReactNode;
}

const LegacyShell: React.FC<LegacyShellProps> = ({ children }) => (
    <Box
        sx={{
            minHeight: "100svh",
            backgroundColor: "background.default",
            color: "text.base",
            display: "flex",
            flexDirection: "column",
        }}
    >
        <Box
            component="header"
            sx={{
                alignItems: "center",
                display: "flex",
                height: { xs: 52, md: 73 },
                justifyContent: "center",
                pt: { xs: 0, md: 3 },
                width: "100%",
            }}
        >
            <Box sx={{ display: { xs: "block", md: "none" }, lineHeight: 0 }}>
                <EnteLogo height={16} />
            </Box>
            <Box sx={{ display: { xs: "none", md: "block" }, lineHeight: 0 }}>
                <EnteLogo height={25.5} />
            </Box>
        </Box>
        <Box
            component="main"
            sx={{
                alignItems: "center",
                display: "flex",
                flex: 1,
                justifyContent: "center",
                minHeight: 0,
                overflow: "hidden auto",
                px: { xs: 2.5, md: 5 },
                py: { xs: 3, md: "1px" },
            }}
        >
            {children}
        </Box>
    </Box>
);

interface LandingStepProps {
    onStart: () => void;
}

const LandingStep: React.FC<LandingStepProps> = ({ onStart }) => (
    <Stack
        direction={{ xs: "column", lg: "row" }}
        sx={{
            alignItems: "center",
            gap: { xs: 2, md: "46px" },
            justifyContent: "center",
            maxWidth: { xs: 343, md: 933 },
            width: "100%",
        }}
    >
        <Box
            component="img"
            alt=""
            src="/images/legacy-kit/recovery-landing.svg"
            sx={{
                height: { xs: "auto", md: 293.566 },
                mt: { xs: 4, md: 0 },
                width: { xs: 200, md: 304.458 },
            }}
        />

        <Stack
            sx={{
                alignItems: "center",
                gap: { xs: 2, md: "42px" },
                maxWidth: { xs: 343, md: 582 },
                textAlign: "center",
                width: "100%",
            }}
        >
            <Stack sx={{ gap: 2, width: "100%" }}>
                <Typography
                    component="h1"
                    sx={{
                        fontSize: { xs: 24, md: 40 },
                        fontWeight: 700,
                        lineHeight: { xs: "28px", md: "44px" },
                    }}
                >
                    Recover an Ente account
                </Typography>
                <Typography
                    sx={{
                        color: "text.muted",
                        fontSize: 16,
                        fontWeight: 500,
                        lineHeight: "24px",
                        mx: "auto",
                        maxWidth: { xs: 311, md: 582 },
                    }}
                >
                    Use your legacy kit recovery sheets to regain access to an
                    Ente account.
                </Typography>
            </Stack>

            <Stack
                component="ul"
                sx={{
                    alignItems: { xs: "flex-start", md: "stretch" },
                    gap: { xs: "17px", md: 3 },
                    listStyle: "none",
                    m: 0,
                    p: 0,
                    textAlign: "left",
                }}
            >
                {[
                    "Have 2 recovery sheets ready",
                    "Upload the recovery sheets",
                    "Recover account after waiting period",
                ].map((feature) => (
                    <Stack
                        component="li"
                        key={feature}
                        direction="row"
                        sx={{ alignItems: "center", gap: 1.5 }}
                    >
                        <Box
                            sx={{
                                backgroundColor: "accent.main",
                                borderRadius: "50%",
                                flexShrink: 0,
                                height: { xs: 5, md: 10 },
                                width: { xs: 5, md: 10 },
                            }}
                        />
                        <Typography
                            sx={{
                                fontSize: { xs: 16, md: 20 },
                                fontWeight: 500,
                                lineHeight: { xs: "20px", md: "20px" },
                            }}
                        >
                            {feature}
                        </Typography>
                    </Stack>
                ))}
            </Stack>

            <Button
                color="accent"
                onClick={onStart}
                sx={{
                    ...buttonSx,
                    borderRadius: { xs: "20px", md: "25px" },
                    fontSize: { xs: 14, md: 16 },
                    height: { xs: 52, md: 65 },
                    maxWidth: { xs: 343, md: 502 },
                    width: "100%",
                }}
            >
                Start recovery
            </Button>
        </Stack>
    </Stack>
);

interface UploadStepProps {
    canOpen: boolean;
    isOpening: boolean;
    onFile: (slotID: SlotID, file: File | undefined) => void;
    onOpen: () => void;
    onText: (slotID: SlotID, value: string) => void;
    openError?: string;
    pairError?: string;
    slots: Record<SlotID, SheetSlot>;
}

const UploadStep: React.FC<UploadStepProps> = ({
    canOpen,
    isOpening,
    onFile,
    onOpen,
    onText,
    openError,
    pairError,
    slots,
}) => (
    <Stack
        sx={{
            alignItems: "center",
            gap: { xs: 4, md: 7 },
            maxWidth: 680,
            width: "100%",
        }}
    >
        <Stack sx={{ alignItems: "center", gap: 2, textAlign: "center" }}>
            <CircleIcon tone="info">
                <CloudUploadOutlinedIcon
                    sx={{ fontSize: { xs: 36, md: 46 } }}
                />
            </CircleIcon>
            <Stack sx={{ gap: 2 }}>
                <Typography
                    component="h1"
                    sx={{
                        fontSize: { xs: 28, md: 32 },
                        fontWeight: 700,
                        lineHeight: { xs: "32px", md: "36px" },
                    }}
                >
                    Upload your recovery sheets
                </Typography>
                <Typography
                    sx={{
                        color: "text.muted",
                        fontSize: 16,
                        fontWeight: 500,
                        lineHeight: "20px",
                        maxWidth: { xs: 335, md: 500 },
                    }}
                >
                    Upload the two recovery sheets, or paste the code text
                    printed below the QR on each sheet.
                </Typography>
            </Stack>
        </Stack>

        <Stack
            direction={{ xs: "column", md: "row" }}
            sx={{
                alignItems: "flex-start",
                gap: { xs: 3, md: "82px" },
                width: { xs: 335, md: "auto" },
            }}
        >
            <SheetInput
                slotID="first"
                slot={slots.first}
                onFile={(file) => onFile("first", file)}
                onText={(value) => onText("first", value)}
            />
            <SheetInput
                slotID="second"
                slot={slots.second}
                onFile={(file) => onFile("second", file)}
                onText={(value) => onText("second", value)}
            />
        </Stack>

        <Stack sx={{ alignItems: "center", gap: 1.5, width: "100%" }}>
            {pairError && (
                <Alert severity="error" sx={{ maxWidth: 420, width: "100%" }}>
                    {pairError}
                </Alert>
            )}
            {openError && (
                <Alert severity="error" sx={{ maxWidth: 420, width: "100%" }}>
                    {openError}
                </Alert>
            )}
            <LoadingButton
                color="accent"
                loading={isOpening}
                disabled={!canOpen}
                onClick={onOpen}
                sx={{ ...buttonSx, maxWidth: 400, width: "100%" }}
            >
                Recover account
            </LoadingButton>
        </Stack>
    </Stack>
);

interface SheetInputProps {
    onFile: (file: File | undefined) => void;
    onText: (value: string) => void;
    slot: SheetSlot;
    slotID: SlotID;
}

const SheetInput: React.FC<SheetInputProps> = ({
    onFile,
    onText,
    slot,
    slotID,
}) => (
    <Stack sx={{ gap: 1.5, width: { xs: "100%", md: 284 } }}>
        <SheetHeader slotID={slotID} isComplete={!!slot.share} />

        {slot.share ? (
            <ScannedSheetCard />
        ) : (
            <>
                <UploadArea slot={slot} onFile={onFile} />
                <Typography
                    sx={{
                        color: "text.muted",
                        fontSize: 12,
                        fontWeight: 700,
                        lineHeight: "16px",
                        textAlign: "center",
                    }}
                >
                    OR
                </Typography>
                <TextField
                    hiddenLabel
                    placeholder="Paste share code here..."
                    value={slot.rawCode}
                    onChange={(event) => onText(event.target.value)}
                    fullWidth
                    slotProps={{ input: { disableUnderline: true } }}
                    sx={textFieldSx}
                />
            </>
        )}
    </Stack>
);

interface SheetHeaderProps {
    isComplete: boolean;
    slotID: SlotID;
}

const SheetHeader: React.FC<SheetHeaderProps> = ({ isComplete, slotID }) => (
    <Stack direction="row" sx={{ alignItems: "center", gap: 1.5 }}>
        {isComplete ? (
            <CheckCircleRoundedIcon
                sx={{ color: "accent.main", fontSize: 24 }}
            />
        ) : (
            <Box
                sx={{
                    alignItems: "center",
                    backgroundColor:
                        slotID === "first" ? "accent.main" : "fill.faint",
                    borderRadius: "50%",
                    color:
                        slotID === "first"
                            ? "accent.contrastText"
                            : "accent.main",
                    display: "flex",
                    fontSize: 12,
                    fontWeight: 600,
                    height: 24,
                    justifyContent: "center",
                    lineHeight: "15px",
                    width: 24,
                }}
            >
                {slotNumbers[slotID]}
            </Box>
        )}
        <Typography sx={{ fontSize: 16, fontWeight: 600, lineHeight: "20px" }}>
            {slotLabels[slotID]}
        </Typography>
    </Stack>
);

interface UploadAreaProps {
    onFile: (file: File | undefined) => void;
    slot: SheetSlot;
}

const UploadArea: React.FC<UploadAreaProps> = ({ onFile, slot }) => (
    <Stack sx={{ gap: 1 }}>
        <Box
            component="label"
            role="button"
            aria-disabled={slot.isReading}
            tabIndex={slot.isReading ? -1 : 0}
            sx={(theme) => ({
                alignItems: "center",
                backgroundColor: "#E7EFFA",
                borderRadius: { xs: "20px", md: "12px" },
                color: "text.muted",
                cursor: slot.isReading ? "default" : "pointer",
                display: "flex",
                flexDirection: "row",
                fontSize: { xs: 14, md: 16 },
                fontWeight: 500,
                gap: 1,
                height: { xs: 52, md: 160 },
                justifyContent: "center",
                lineHeight: "20px",
                outline: "none",
                p: { xs: 2, md: 3 },
                position: "relative",
                textAlign: "center",
                width: "100%",
                "&:focus-visible": {
                    boxShadow: "0 0 0 2px var(--mui-palette-accent-main)",
                },
                ...theme.applyStyles("dark", {
                    backgroundColor: "rgba(16, 113, 255, 0.16)",
                }),
            })}
        >
            {slot.isReading ? (
                <CircularProgress size={24} color="accent" />
            ) : (
                <CloudUploadOutlinedIcon
                    sx={{ color: "accent.main", fontSize: 24 }}
                />
            )}
            <span>
                {slot.isReading ? "Reading sheet" : "Upload recovery sheet"}
            </span>
            <Box
                component="input"
                type="file"
                accept="application/pdf,image/*,.txt,text/plain"
                disabled={slot.isReading}
                sx={{
                    clip: "rect(0 0 0 0)",
                    clipPath: "inset(50%)",
                    height: 1,
                    overflow: "hidden",
                    position: "absolute",
                    whiteSpace: "nowrap",
                    width: 1,
                }}
                onChange={(event) => {
                    onFile(event.target.files?.[0]);
                    event.target.value = "";
                }}
            />
        </Box>

        {slot.error && (
            <Typography
                sx={{
                    color: "critical.main",
                    fontSize: 12,
                    fontWeight: 600,
                    lineHeight: "16px",
                    textAlign: "center",
                }}
            >
                {slot.error}
            </Typography>
        )}
    </Stack>
);

const ScannedSheetCard: React.FC = () => (
    <Box
        sx={{
            background: "linear-gradient(180deg, #1071FF 0%, #0A4499 100%)",
            borderRadius: { xs: "20px", md: "35px" },
            color: "fixed.white",
            height: { xs: 76, md: 252 },
            overflow: "hidden",
            position: "relative",
            px: { xs: 2.5, md: "25px" },
            py: { xs: 2, md: "31px" },
            width: "100%",
        }}
    >
        <CheckCircleRoundedIcon
            sx={{
                color: "fixed.white",
                fontSize: { xs: 28, md: 48 },
                opacity: 0.95,
                position: "absolute",
                right: { xs: 20, md: 22 },
                top: { xs: 22, md: 31 },
            }}
        />
        <Typography
            sx={{
                bottom: { xs: 18, md: 29 },
                fontSize: { xs: 18, md: 24 },
                fontWeight: 700,
                left: { xs: 20, md: 25 },
                lineHeight: { xs: "20px", md: "24px" },
                maxWidth: { xs: 210, md: 237 },
                position: "absolute",
            }}
        >
            Sheet
            <Box component="span" sx={{ display: "block", fontWeight: 500 }}>
                scanned successfully
            </Box>
        </Typography>
    </Box>
);

const inactiveLegacyKitDescription =
    "This legacy kit has been deleted by the account owner. These recovery sheets can no longer be used. Contact the account owner for help.";

const InactiveLegacyKitStep: React.FC = () => (
    <Stack
        sx={{
            alignItems: "center",
            gap: { xs: 2.5, md: 3.5 },
            maxWidth: { xs: 311, md: 560 },
            p: { xs: 0, md: 6 },
            textAlign: "center",
            width: "100%",
        }}
    >
        <Box
            component="img"
            alt=""
            src="/images/legacy-kit/kit-no-longer-active.svg"
            sx={{ height: "97.261px", width: "103.266px" }}
        />
        <Stack sx={{ alignItems: "center", gap: { xs: 1.5, md: 2 } }}>
            <Typography
                component="h1"
                sx={{
                    fontSize: { xs: 24, md: 32 },
                    fontWeight: 800,
                    lineHeight: { xs: "28px", md: "36px" },
                }}
            >
                Kit no longer active
            </Typography>
            <Typography
                sx={{
                    color: "text.muted",
                    fontSize: { xs: 12, md: 16 },
                    fontWeight: 500,
                    lineHeight: { xs: "16px", md: "20px" },
                }}
            >
                {inactiveLegacyKitDescription}
            </Typography>
        </Stack>
    </Stack>
);

interface WaitingStepProps {
    isRefreshing: boolean;
    openError?: string;
    session: LegacyKitRecoverySession;
}

const WaitingStep: React.FC<WaitingStepProps> = ({
    isRefreshing,
    openError,
    session,
}) => (
    <StatusLayout
        icon={
            <CircleIcon tone="info">
                {isRefreshing ? (
                    <CircularProgress size={42} color="accent" />
                ) : (
                    <AccessTimeRoundedIcon sx={{ fontSize: 48 }} />
                )}
            </CircleIcon>
        }
        title="Recovery pending"
    >
        <Stack sx={{ alignItems: "center", gap: 1, textAlign: "center" }}>
            <Typography sx={{ color: "text.muted", lineHeight: "20px" }}>
                The account owner has set a waiting period. You can recover the
                account after
            </Typography>
            <Typography sx={{ fontWeight: 600, lineHeight: "20px" }}>
                {displayWaitTarget(session.waitTill)}
            </Typography>
        </Stack>
        <Typography
            sx={{
                color: "text.muted",
                lineHeight: "20px",
                textAlign: "center",
            }}
        >
            Come back after this time to gain access
        </Typography>
        {openError && <Alert severity="error">{openError}</Alert>}
    </StatusLayout>
);

interface ResetPasswordStepProps {
    onSubmit: (
        password: string,
        setPasswordsFieldError: (message: string) => void,
    ) => Promise<void>;
}

const ResetPasswordStep: React.FC<ResetPasswordStepProps> = ({ onSubmit }) => (
    <StatusLayout
        icon={
            <CircleIcon tone="success">
                <LockResetRoundedIcon sx={{ fontSize: 48 }} />
            </CircleIcon>
        }
        title="Reset password"
        description="Your recovery sheets have been verified. Choose a new password."
        contentWidth={420}
    >
        <LegacyPasswordForm onSubmit={onSubmit} />
    </StatusLayout>
);

interface LegacyPasswordFormProps {
    onSubmit: (
        password: string,
        setPasswordsFieldError: (message: string) => void,
    ) => Promise<void>;
}

const LegacyPasswordForm: React.FC<LegacyPasswordFormProps> = ({
    onSubmit,
}) => {
    const [password, setPassword] = useState("");
    const [confirmPassword, setConfirmPassword] = useState("");
    const [showPassword, setShowPassword] = useState(false);
    const [showConfirmPassword, setShowConfirmPassword] = useState(false);
    const [fieldError, setFieldError] = useState("");
    const [isSubmitting, setIsSubmitting] = useState(false);

    const canSubmit =
        !!password &&
        !!confirmPassword &&
        !isWeakPassword(password) &&
        !isSubmitting;

    const submit = async (event: React.SubmitEvent) => {
        event.preventDefault();
        setFieldError("");

        if (isWeakPassword(password)) {
            setFieldError("Use a stronger password.");
            return;
        }
        if (password !== confirmPassword) {
            setFieldError("Passwords do not match.");
            return;
        }

        setIsSubmitting(true);
        try {
            await onSubmit(password, setFieldError);
        } finally {
            setIsSubmitting(false);
        }
    };

    return (
        <Stack
            component="form"
            onSubmit={submit}
            sx={{ gap: 1.5, width: "100%" }}
        >
            <LabeledPasswordField
                label="New password"
                value={password}
                showPassword={showPassword}
                disabled={isSubmitting}
                onChange={(value) => {
                    setPassword(value);
                    setFieldError("");
                }}
                onToggle={() => setShowPassword((show) => !show)}
            />
            <LabeledPasswordField
                label="Confirm password"
                value={confirmPassword}
                showPassword={showConfirmPassword}
                disabled={isSubmitting}
                error={fieldError}
                onChange={(value) => {
                    setConfirmPassword(value);
                    setFieldError("");
                }}
                onToggle={() => setShowConfirmPassword((show) => !show)}
            />
            <LoadingButton
                color="accent"
                type="submit"
                loading={isSubmitting}
                disabled={!canSubmit}
                sx={{ ...buttonSx, mt: 0.5, width: "100%" }}
            >
                Reset password
            </LoadingButton>
        </Stack>
    );
};

interface LabeledPasswordFieldProps {
    disabled: boolean;
    error?: string;
    label: string;
    onChange: (value: string) => void;
    onToggle: () => void;
    showPassword: boolean;
    value: string;
}

const LabeledPasswordField: React.FC<LabeledPasswordFieldProps> = ({
    disabled,
    error,
    label,
    onChange,
    onToggle,
    showPassword,
    value,
}) => (
    <Stack sx={{ gap: 1 }}>
        <Typography sx={{ fontSize: 14, fontWeight: 500, lineHeight: "20px" }}>
            {label}
        </Typography>
        <TextField
            hiddenLabel
            type={showPassword ? "text" : "password"}
            value={value}
            onChange={(event) => onChange(event.target.value)}
            disabled={disabled}
            error={!!error}
            helperText={error || " "}
            fullWidth
            autoComplete="new-password"
            slotProps={{
                input: {
                    disableUnderline: true,
                    endAdornment: (
                        <ShowHidePasswordInputAdornment
                            showPassword={showPassword}
                            onToggle={onToggle}
                        />
                    ),
                },
            }}
            sx={textFieldSx}
        />
    </Stack>
);

interface TerminalStatusStepProps {
    session: LegacyKitRecoverySession;
}

const TerminalStatusStep: React.FC<TerminalStatusStepProps> = ({ session }) => {
    if (session.status === "RECOVERED") {
        return (
            <StatusLayout
                icon={
                    <CircleIcon tone="success">
                        <CheckCircleRoundedIcon sx={{ fontSize: 48 }} />
                    </CircleIcon>
                }
                title="Password reset complete"
                description="You can now sign in with your new password."
            />
        );
    }

    const title =
        session.status === "BLOCKED"
            ? "Recovery blocked"
            : "Recovery cancelled";
    const description =
        session.status === "BLOCKED"
            ? "The account owner blocked this recovery attempt."
            : "This recovery attempt was cancelled.";

    return (
        <StatusLayout
            icon={
                <CircleIcon tone="critical">
                    <ErrorOutlineRoundedIcon sx={{ fontSize: 48 }} />
                </CircleIcon>
            }
            title={title}
            description={description}
        />
    );
};

interface StatusLayoutProps {
    children?: React.ReactNode;
    contentWidth?: number;
    description?: string;
    icon: React.ReactNode;
    title: string;
}

const StatusLayout: React.FC<StatusLayoutProps> = ({
    children,
    contentWidth = 560,
    description,
    icon,
    title,
}) => (
    <Stack
        sx={{
            alignItems: "center",
            gap: 3.5,
            maxWidth: contentWidth,
            pb: { md: "86px" },
            px: { xs: 1.5, md: 6 },
            py: { xs: 4, md: 6 },
            textAlign: "center",
            width: "100%",
        }}
    >
        {icon}
        <Stack sx={{ alignItems: "center", gap: 2, width: "100%" }}>
            <Typography
                component="h1"
                sx={{ fontSize: 32, fontWeight: 700, lineHeight: "36px" }}
            >
                {title}
            </Typography>
            {description && (
                <Typography
                    sx={{
                        color: "text.muted",
                        fontSize: 16,
                        fontWeight: 500,
                        lineHeight: "20px",
                        maxWidth: 460,
                    }}
                >
                    {description}
                </Typography>
            )}
        </Stack>
        {children}
    </Stack>
);

interface CircleIconProps {
    children: React.ReactNode;
    tone: "critical" | "info" | "success";
}

const CircleIcon: React.FC<CircleIconProps> = ({ children, tone }) => {
    const colors = {
        critical: { bg: "rgba(234, 63, 63, 0.12)", color: "critical.main" },
        info: { bg: "rgba(16, 113, 255, 0.12)", color: "accent.main" },
        success: { bg: "rgba(29, 185, 84, 0.12)", color: "success.main" },
    }[tone];

    return (
        <Box
            sx={{
                alignItems: "center",
                backgroundColor: colors.bg,
                borderRadius: "50%",
                color: colors.color,
                display: "flex",
                height: { xs: 80, md: 100 },
                justifyContent: "center",
                width: { xs: 80, md: 100 },
            }}
        >
            {children}
        </Box>
    );
};

export default Page;
