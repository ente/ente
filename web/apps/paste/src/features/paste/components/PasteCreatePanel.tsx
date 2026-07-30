import { usePasteColorMode } from "@/features/paste/hooks/usePasteColorMode";
import { getPasteThemeTokens } from "@/features/paste/theme/pasteThemeTokens";
import { Navigation06Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import LockOpenRoundedIcon from "@mui/icons-material/LockOpenRounded";
import LockRoundedIcon from "@mui/icons-material/LockRounded";
import {
    Box,
    Button,
    CircularProgress,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    IconButton,
    Stack,
    TextField,
    Tooltip,
    Typography,
} from "@mui/material";
import { ShowHidePasswordInputAdornment } from "ente-base/components/mui/PasswordInputAdornment";
import type { SubmitEvent } from "react";
import { useState } from "react";
import { MAX_PASTE_CHARS } from "../constants";
import { PasteLinkCard } from "./PasteLinkCard";
import { downloadPasteQrCode } from "./qrCode";
import { pasteTextFieldSx } from "./textFieldSx";

interface PasteCreatePanelProps {
    inputText: string;
    creating: boolean;
    createError: string | null;
    createdLink: string | null;
    createdLinkPasswordProtected: boolean;
    onInputChange: (value: string) => void;
    onCreate: (password?: string) => Promise<void>;
    onCopyLink: (value: string) => Promise<void>;
    onShareLink: (url: string) => Promise<void>;
}

export const PasteCreatePanel = ({
    inputText,
    creating,
    createError,
    createdLink,
    createdLinkPasswordProtected,
    onInputChange,
    onCreate,
    onCopyLink,
    onShareLink,
}: PasteCreatePanelProps) => {
    const { resolvedMode } = usePasteColorMode();
    const tokens = getPasteThemeTokens(resolvedMode);
    const [passwordProtected, setPasswordProtected] = useState(false);
    const [passwordDialogOpen, setPasswordDialogOpen] = useState(false);
    const [password, setPassword] = useState("");
    const [confirmPassword, setConfirmPassword] = useState("");
    const [showPassword, setShowPassword] = useState(false);
    const [showConfirmPassword, setShowConfirmPassword] = useState(false);
    const [passwordError, setPasswordError] = useState<string | null>(null);
    const isInputEmpty = inputText.trim().length === 0;
    const nearLimitThreshold = Math.floor(MAX_PASTE_CHARS * 0.9);
    const isNearCharLimit = inputText.length >= nearLimitThreshold;
    const isCreateDisabled = isInputEmpty;
    const passwordTooltip = passwordProtected
        ? "Password protection enabled"
        : "Password protect";
    const errorColor =
        resolvedMode === "dark"
            ? "rgba(255, 139, 160, 0.9)"
            : "rgba(178, 42, 72, 0.9)";
    const passwordDialogBg = resolvedMode === "dark" ? "#0d1016" : "#f8fbff";
    const passwordFieldBg = resolvedMode === "dark" ? "#191c22" : "#ffffff";
    const passwordFieldHoverBg =
        resolvedMode === "dark" ? "#20232b" : "#f4f8ff";
    const passwordDialogShadow =
        resolvedMode === "dark"
            ? "0 22px 56px rgba(0, 0, 0, 0.48)"
            : "0 18px 44px rgba(17, 49, 114, 0.18)";
    const privacyPills = [
        { key: "private", label: "Private" },
        {
            key: "e2ee",
            label: (
                <>
                    <Box
                        component="span"
                        sx={{ display: { xs: "inline", sm: "none" } }}
                    >
                        E2EE
                    </Box>
                    <Box
                        component="span"
                        sx={{ display: { xs: "none", sm: "inline" } }}
                    >
                        End-to-end encrypted
                    </Box>
                </>
            ),
        },
        { key: "one-time-view", label: "One-time view" },
        { key: "auto-delete", label: "Auto-deletes after 24 hours" },
    ];
    const passwordFieldSx = {
        ...pasteTextFieldSx(tokens, "14px"),
        "& .MuiFilledInput-root": {
            borderRadius: "12px",
            bgcolor: resolvedMode === "dark" ? "transparent" : passwordFieldBg,
            border: "1px solid",
            borderColor: tokens.surface.inputBorder,
            boxSizing: "border-box",
            minHeight: 48,
            alignItems: "center",
            px: 1.45,
            py: 0,
            background:
                resolvedMode === "dark" ? "transparent" : passwordFieldBg,
            boxShadow: "none",
            transition:
                "background 180ms ease, border-color 180ms ease, box-shadow 180ms ease",
            "&:before, &:after": {
                display: "none",
                borderBottom: "0 !important",
            },
            "&:hover:not(.Mui-disabled, .Mui-error):before": {
                display: "none",
                borderBottom: "0 !important",
            },
            "&:hover": {
                bgcolor:
                    resolvedMode === "dark"
                        ? "rgba(255, 255, 255, 0.03)"
                        : passwordFieldHoverBg,
                borderColor: tokens.surface.inputBorder,
                background:
                    resolvedMode === "dark"
                        ? "rgba(255, 255, 255, 0.03)"
                        : passwordFieldHoverBg,
                boxShadow: "none",
            },
            "&.Mui-focused": {
                bgcolor:
                    resolvedMode === "dark"
                        ? "rgba(255, 255, 255, 0.035)"
                        : passwordFieldBg,
                borderColor: tokens.button.primaryBg,
                background:
                    resolvedMode === "dark"
                        ? "rgba(255, 255, 255, 0.035)"
                        : passwordFieldBg,
                boxShadow: `0 0 0 2px ${tokens.accent.soft}`,
            },
            "&.Mui-error": { borderColor: errorColor },
        },
        "& .MuiInputBase-input": {
            color: tokens.text.primary,
            fontSize: { xs: "0.92rem", sm: "0.95rem" },
            lineHeight: 1.35,
            padding: "0 !important",
            borderBottom: "0 !important",
            boxShadow: "none",
        },
        "& .MuiFilledInput-underline:before, & .MuiFilledInput-underline:after":
            { display: "none", borderBottom: "0 !important" },
        "& .MuiInputAdornment-root": { ml: 0.75, mr: 0.5 },
        "& .MuiIconButton-root": {
            p: 0.75,
            color: tokens.text.placeholder,
            "&:hover": {
                color: tokens.text.primary,
                bgcolor:
                    resolvedMode === "dark"
                        ? "rgba(255, 255, 255, 0.06)"
                        : "rgba(17, 49, 114, 0.06)",
            },
        },
        "& .MuiIconButton-edgeEnd": { mr: 0 },
        "& .MuiSvgIcon-root": { fontSize: 19 },
        "& input::placeholder": { color: tokens.text.placeholder, opacity: 1 },
        "& .MuiFormHelperText-root": {
            mx: 0,
            mt: 0.65,
            color: tokens.text.subtle,
            fontSize: "0.78rem",
            lineHeight: 1.25,
        },
        "& .MuiFormHelperText-root.Mui-error": { color: errorColor },
    };

    const resetPasswordDialog = () => {
        setPassword("");
        setConfirmPassword("");
        setShowPassword(false);
        setShowConfirmPassword(false);
        setPasswordError(null);
    };

    const togglePasswordVisibility = () => {
        setShowPassword((visible) => !visible);
    };

    const toggleConfirmPasswordVisibility = () => {
        setShowConfirmPassword((visible) => !visible);
    };

    const handlePasswordSubmit = (event: SubmitEvent) => {
        event.preventDefault();
        if (!password) {
            setPasswordError("Enter a password");
            return;
        }
        if (password !== confirmPassword) {
            setPasswordError("Passwords do not match");
            return;
        }

        const submittedPassword = password;
        setPasswordDialogOpen(false);
        resetPasswordDialog();
        void onCreate(submittedPassword);
    };

    const handleDownloadQrClick = () => {
        if (!createdLink) return;

        void downloadPasteQrCode({
            value: createdLink,
            tokens,
            paperBg: tokens.qr.paperBg,
            showCenterLock: createdLinkPasswordProtected,
        }).catch(() => undefined);
    };

    return (
        <Box sx={{ width: "100%", maxWidth: "100%", minWidth: 0 }}>
            <Box
                sx={{
                    position: "relative",
                    width: "100%",
                    maxWidth: "100%",
                    minWidth: 0,
                }}
            >
                <TextField
                    variant="filled"
                    hiddenLabel
                    fullWidth
                    slotProps={{
                        input: { disableUnderline: true },
                        htmlInput: {
                            maxLength: MAX_PASTE_CHARS,
                            "aria-label": "Paste text",
                        },
                    }}
                    multiline
                    minRows={5}
                    maxRows={12}
                    placeholder="Paste text (keys, snippets, notes, instructions...)"
                    value={inputText}
                    onChange={(event) => {
                        onInputChange(event.target.value);
                    }}
                    sx={[
                        pasteTextFieldSx(tokens, "20px"),
                        {
                            "& .MuiFilledInput-root": {
                                paddingTop: { xs: "12px", sm: "14px" },
                                paddingRight: { xs: "12px", sm: "14px" },
                                paddingLeft: { xs: "12px", sm: "14px" },
                                // Keep only the minimum reserve needed for the footer row.
                                paddingBottom: { xs: "50px", sm: "56px" },
                                backdropFilter: "blur(9px) saturate(112%)",
                                WebkitBackdropFilter:
                                    "blur(9px) saturate(112%)",
                                background: tokens.surface.inputGradient,
                                boxShadow: tokens.surface.inputShadow,
                                "&:hover": {
                                    bgcolor: tokens.surface.inputBg,
                                    borderColor: tokens.surface.inputBorder,
                                    background: tokens.surface.inputGradient,
                                    boxShadow: tokens.surface.inputShadow,
                                },
                                "&.Mui-focused": {
                                    bgcolor: tokens.surface.inputBg,
                                    borderColor: tokens.surface.inputBorder,
                                    background: tokens.surface.inputGradient,
                                    boxShadow: tokens.surface.inputShadow,
                                },
                            },
                            "& .MuiInputBase-input": {
                                fontSize: { xs: "0.9rem", sm: "0.96rem" },
                                lineHeight: 1.6,
                            },
                        },
                    ]}
                />
                <Box
                    sx={{
                        position: "absolute",
                        left: { xs: 12, sm: 18 },
                        right: { xs: 12, sm: 18 },
                        bottom: { xs: 8, sm: 10 },
                        height: { xs: 36, sm: 40 },
                        display: "flex",
                        justifyContent: "space-between",
                        alignItems: "center",
                        gap: { xs: 1, sm: 2 },
                        pointerEvents: "none",
                    }}
                >
                    <Box
                        sx={{
                            display: "flex",
                            alignItems: "center",
                            gap: 0.7,
                            height: { xs: 32, sm: 36 },
                            pointerEvents: "auto",
                        }}
                    >
                        <Typography
                            component="span"
                            variant="mini"
                            sx={{
                                display: "flex",
                                alignItems: "center",
                                flexShrink: 0,
                                color: tokens.text.counter,
                                fontVariantNumeric: "tabular-nums",
                                fontFeatureSettings: '"tnum"',
                                fontWeight: 600,
                                lineHeight: 1,
                                letterSpacing: "0.01em",
                            }}
                        >
                            <Box
                                component="span"
                                sx={{
                                    color: isNearCharLimit
                                        ? tokens.text.counterHighlight
                                        : tokens.text.counter,
                                }}
                            >
                                {inputText.length}
                            </Box>
                            <Box
                                component="span"
                                sx={{ color: tokens.text.counter }}
                            >
                                /{MAX_PASTE_CHARS}
                            </Box>
                        </Typography>
                        <Tooltip title={passwordTooltip} arrow>
                            <IconButton
                                aria-label={
                                    passwordProtected
                                        ? "Disable password protection"
                                        : "Enable password protection"
                                }
                                aria-pressed={passwordProtected}
                                onClick={() => {
                                    if (creating) return;
                                    setPasswordProtected((enabled) => !enabled);
                                }}
                                sx={{
                                    width: { xs: 30, sm: 32 },
                                    height: { xs: 30, sm: 32 },
                                    color: passwordProtected
                                        ? tokens.button.primaryBg
                                        : tokens.text.counter,
                                    bgcolor: passwordProtected
                                        ? tokens.surface.chipBg
                                        : "transparent",
                                    "&:hover": {
                                        bgcolor: tokens.surface.chipBg,
                                    },
                                }}
                            >
                                {passwordProtected ? (
                                    <LockRoundedIcon sx={{ fontSize: 17 }} />
                                ) : (
                                    <LockOpenRoundedIcon
                                        sx={{ fontSize: 17 }}
                                    />
                                )}
                            </IconButton>
                        </Tooltip>
                    </Box>
                    <IconButton
                        aria-label="Create secure link"
                        aria-busy={creating}
                        onClick={() => {
                            if (creating || isCreateDisabled) return;
                            if (passwordProtected) {
                                setPasswordDialogOpen(true);
                            } else {
                                void onCreate();
                            }
                        }}
                        disabled={isCreateDisabled}
                        sx={{
                            pointerEvents: "auto",
                            boxSizing: "border-box",
                            width: { xs: 34, sm: 38 },
                            height: { xs: 34, sm: 38 },
                            minWidth: { xs: 34, sm: 38 },
                            minHeight: { xs: 34, sm: 38 },
                            padding: 0,
                            marginBottom: { xs: "3px", sm: "4px" },
                            marginRight: { xs: "-1px", sm: "-2px" },
                            borderRadius: { xs: "12px", sm: "14px" },
                            bgcolor: tokens.button.primaryBg,
                            color: tokens.button.primaryText,
                            boxShadow: "none",
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            "&:hover": {
                                bgcolor: tokens.button.primaryHoverBg,
                                boxShadow: "none",
                            },
                            "&.Mui-disabled": {
                                bgcolor: tokens.button.primaryDisabledBg,
                                color: tokens.button.primaryDisabledText,
                            },
                        }}
                    >
                        {creating ? (
                            <Box
                                sx={{
                                    width: 18,
                                    height: 18,
                                    display: "flex",
                                    alignItems: "center",
                                    justifyContent: "center",
                                    lineHeight: 0,
                                }}
                            >
                                <CircularProgress
                                    size={17}
                                    thickness={5.2}
                                    sx={{
                                        color: tokens.button.primaryText,
                                        display: "block",
                                        "& .MuiCircularProgress-svg": {
                                            display: "block",
                                            transformOrigin: "50% 50%",
                                        },
                                    }}
                                />
                            </Box>
                        ) : (
                            <Box
                                sx={{
                                    transform: "rotate(90deg)",
                                    display: "flex",
                                }}
                            >
                                <HugeiconsIcon
                                    icon={Navigation06Icon}
                                    size={18}
                                    strokeWidth={2}
                                />
                            </Box>
                        )}
                    </IconButton>
                </Box>
            </Box>
            <Box
                sx={{
                    mt: { xs: "16px" },
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    textAlign: "center",
                    width: "100%",
                    maxWidth: "100%",
                }}
            >
                <Box
                    sx={{
                        display: "flex",
                        flexWrap: "wrap",
                        justifyContent: "center",
                        gap: { xs: 0.7, sm: 1 },
                        width: "100%",
                        maxWidth: { xs: "100%", sm: 520, md: "none" },
                        mb: { xs: "2rem", sm: "3rem" },
                        pointerEvents: "none",
                        userSelect: "none",
                    }}
                >
                    {privacyPills.map(({ key, label }) => (
                        <Box
                            key={key}
                            component="span"
                            aria-disabled="true"
                            sx={{
                                px: { xs: 1.2, sm: 1.4 },
                                py: { xs: 0.45, sm: 0.6 },
                                borderRadius: "999px",
                                border: `1px solid ${tokens.surface.chipBorder}`,
                                bgcolor: tokens.surface.chipBg,
                                color: tokens.surface.chipText,
                                fontSize: { xs: "0.74rem", sm: "0.79rem" },
                                fontWeight: 600,
                                letterSpacing: "0.01em",
                                lineHeight: 1.2,
                                whiteSpace: "nowrap",
                                boxShadow: tokens.surface.chipInsetShadow,
                                opacity: 0.78,
                            }}
                        >
                            {label}
                        </Box>
                    ))}
                </Box>
            </Box>

            {createError && (
                <Typography sx={{ color: "error.main" }}>
                    {createError}
                </Typography>
            )}

            {createdLink && (
                <Box sx={{ mt: 0, width: "100%", minWidth: 0 }}>
                    <PasteLinkCard
                        link={createdLink}
                        onCopy={onCopyLink}
                        onShare={onShareLink}
                        passwordProtected={createdLinkPasswordProtected}
                    />
                    <Box
                        sx={{
                            mt: 0.85,
                            display: "flex",
                            justifyContent: "flex-start",
                        }}
                    >
                        <Typography
                            component="button"
                            type="button"
                            variant="mini"
                            onClick={handleDownloadQrClick}
                            sx={{
                                appearance: "none",
                                border: 0,
                                p: 0,
                                m: 0,
                                bgcolor: "transparent",
                                color: tokens.text.muted,
                                cursor: "pointer",
                                fontSize: { xs: "0.68rem", sm: "0.72rem" },
                                fontWeight: 600,
                                lineHeight: 1.3,
                                letterSpacing: 0,
                                opacity: 0.6,
                                textDecoration: "underline",
                                textUnderlineOffset: "3px",
                                "&:hover": {
                                    color: tokens.text.muted,
                                    opacity: 0.72,
                                    textDecoration: "underline",
                                },
                                "&:focus-visible": {
                                    outline: `2px solid ${tokens.button.primaryBg}`,
                                    outlineOffset: 3,
                                    borderRadius: "4px",
                                },
                            }}
                        >
                            Download QR
                        </Typography>
                    </Box>
                </Box>
            )}

            <Dialog
                open={passwordDialogOpen}
                onClose={() => {
                    setPasswordDialogOpen(false);
                    resetPasswordDialog();
                }}
                fullWidth
                maxWidth="xs"
                slotProps={{
                    backdrop: {
                        sx: { bgcolor: tokens.surface.dialogBackdrop },
                    },
                    paper: {
                        component: "form",
                        onSubmit: handlePasswordSubmit,
                        sx: {
                            mx: { xs: 2.5, sm: 3 },
                            p: { xs: "24px 20px 26px", sm: "28px 26px 30px" },
                            borderRadius: "24px",
                            border: "1px solid",
                            borderColor: tokens.surface.dialogBorder,
                            boxSizing: "border-box",
                            bgcolor: passwordDialogBg,
                            background:
                                resolvedMode === "dark"
                                    ? "rgba(13, 16, 22, 0.78)"
                                    : "rgba(248, 251, 255, 0.82)",
                            backdropFilter: "blur(16px) saturate(118%)",
                            WebkitBackdropFilter: "blur(16px) saturate(118%)",
                            color: tokens.text.primary,
                            boxShadow: passwordDialogShadow,
                            overflow: "hidden",
                        },
                    },
                }}
            >
                <DialogTitle
                    component="div"
                    sx={{
                        p: 0,
                        ml: { xs: -1.4, sm: -1.6 },
                        color: tokens.text.primary,
                    }}
                >
                    <Typography
                        component="h2"
                        sx={{
                            m: 0,
                            color: tokens.text.primary,
                            fontSize: { xs: "1.24rem", sm: "1.38rem" },
                            fontWeight: 750,
                            lineHeight: 1.18,
                        }}
                    >
                        Paste password
                    </Typography>
                    <Typography
                        sx={{
                            mt: 0.5,
                            color: tokens.text.muted,
                            fontSize: { xs: "0.86rem", sm: "0.9rem" },
                            fontWeight: 500,
                            lineHeight: 1.45,
                        }}
                    >
                        This password will be required to unlock this paste.
                    </Typography>
                </DialogTitle>
                <DialogContent sx={{ p: "0 !important", mt: 2.25 }}>
                    <Stack spacing={1.5}>
                        <TextField
                            autoFocus
                            variant="filled"
                            hiddenLabel
                            fullWidth
                            type={showPassword ? "text" : "password"}
                            placeholder="Password"
                            value={password}
                            autoComplete="off"
                            slotProps={{
                                htmlInput: { "aria-label": "Password" },
                                input: {
                                    disableUnderline: true,
                                    endAdornment: (
                                        <ShowHidePasswordInputAdornment
                                            showPassword={showPassword}
                                            onToggle={togglePasswordVisibility}
                                        />
                                    ),
                                },
                            }}
                            sx={passwordFieldSx}
                            onChange={(event) => {
                                setPassword(event.target.value);
                                setPasswordError(null);
                            }}
                        />
                        <TextField
                            variant="filled"
                            hiddenLabel
                            fullWidth
                            type={showConfirmPassword ? "text" : "password"}
                            placeholder="Confirm password"
                            value={confirmPassword}
                            autoComplete="off"
                            error={!!passwordError}
                            helperText={passwordError}
                            slotProps={{
                                htmlInput: { "aria-label": "Confirm password" },
                                input: {
                                    disableUnderline: true,
                                    endAdornment: (
                                        <ShowHidePasswordInputAdornment
                                            showPassword={showConfirmPassword}
                                            onToggle={
                                                toggleConfirmPasswordVisibility
                                            }
                                        />
                                    ),
                                },
                            }}
                            sx={passwordFieldSx}
                            onChange={(event) => {
                                setConfirmPassword(event.target.value);
                                setPasswordError(null);
                            }}
                        />
                    </Stack>
                </DialogContent>
                <DialogActions
                    sx={{
                        gap: 1.1,
                        p: "0 !important",
                        mt: { xs: 3, sm: 3.75 },
                    }}
                >
                    <Button
                        variant="outlined"
                        sx={{
                            minHeight: 40,
                            minWidth: 96,
                            px: 1.8,
                            borderRadius: "999px",
                            textTransform: "none",
                            fontSize: "0.9rem",
                            fontWeight: 600,
                            letterSpacing: "0.01em",
                            borderColor: tokens.button.ghostBorder,
                            color: tokens.button.ghostText,
                            "&:hover": {
                                borderColor: tokens.button.ghostHoverBorder,
                                bgcolor: tokens.button.ghostHoverBg,
                            },
                        }}
                        onClick={() => {
                            setPasswordDialogOpen(false);
                            resetPasswordDialog();
                        }}
                    >
                        Cancel
                    </Button>
                    <Button
                        type="submit"
                        variant="contained"
                        disableElevation
                        sx={{
                            minHeight: 40,
                            minWidth: 96,
                            px: 1.8,
                            borderRadius: "999px",
                            textTransform: "none",
                            fontSize: "0.9rem",
                            fontWeight: 600,
                            letterSpacing: "0.01em",
                            bgcolor: tokens.button.primaryBg,
                            color: tokens.button.primaryText,
                            boxShadow: "0 2px 8px rgba(47, 109, 247, 0.2)",
                            "&:hover": {
                                bgcolor: tokens.button.primaryHoverBg,
                                boxShadow:
                                    "0 3px 10px rgba(47, 109, 247, 0.24)",
                            },
                        }}
                    >
                        Create
                    </Button>
                </DialogActions>
            </Dialog>
        </Box>
    );
};
