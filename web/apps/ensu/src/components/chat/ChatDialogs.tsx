import { isTauriRuntime as detectTauriAppRuntime } from "@/services/tauri-runtime";
import {
    ArrowRight01Icon,
    Bug01Icon,
    Cancel01Icon,
    File01Icon,
    InformationCircleIcon,
    Settings01Icon,
    SlidersHorizontalIcon,
    Upload01Icon,
    ViewIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    Button,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    IconButton,
    ListItemButton,
    MenuItem,
    Stack,
    TextField,
    Typography,
} from "@mui/material";
import type { SxProps, Theme } from "@mui/material/styles";
import {
    Notification,
    type NotificationAttributes,
} from "ente-base/components/Notification";
import React, { memo } from "react";

interface IconProps {
    size: number;
    strokeWidth: number;
}

interface SuggestedModel {
    id: string;
    name: string;
}

type ModelGateStatus =
    | "checking"
    | "missing"
    | "preloading"
    | "downloading"
    | "ready"
    | "error";

type SxEntry = Exclude<SxProps<Theme>, readonly unknown[]>;

export interface ModelSettingsDraft {
    modelId: string;
    contextLength: string;
    maxTokens: string;
}

export interface ChatDialogsProps {
    showSettingsModal: boolean;
    closeSettingsModal: () => void;
    dialogPaperSx: SxEntry;
    dialogTitleSx: SxEntry;
    actionButtonSx: SxEntry;
    settingsItemSx: SxEntry;
    smallIconProps: IconProps;
    compactIconProps: IconProps;
    saveLogs: () => void | Promise<void>;
    handleCheckForUpdates: () => void | Promise<void>;
    advancedUnlocked: boolean;
    buildVersion?: string;
    handleBuildVersionTap: () => void;
    openModelSettings: () => void;
    openSystemPromptSettings: () => void;
    isSmall: boolean;
    deleteSessionId: string | null;
    deleteSessionLabel: string;
    handleCancelDeleteSession: () => void;
    handleConfirmDeleteSession: () => void | Promise<void>;
    showModelSettings: boolean;
    closeModelSettings: () => void;
    selectedModelId: string;
    defaultModelName: string;
    loadedModelName: string | null;
    isTauriRuntime: boolean;
    suggestedModels: SuggestedModel[];
    contextLength: string;
    maxTokens: string;
    isSavingModel: boolean;
    handleSaveModel: (draft: ModelSettingsDraft) => void;
    handleUseDefaultModel: () => void;
    showSystemPromptSettings: boolean;
    closeSystemPromptSettings: () => void;
    systemPrompt: string;
    handleSaveSystemPrompt: (promptText: string) => void;
    handleUseDefaultSystemPrompt: () => void;
    chatNotificationOpen: boolean;
    setChatNotificationOpen: React.Dispatch<React.SetStateAction<boolean>>;
    chatNotification?: NotificationAttributes;
    modelGateStatus: ModelGateStatus;
    imagePreview: { url: string; name: string } | null;
    closeImagePreview: () => void;
}

export const ChatDialogs = memo(
    ({
        showSettingsModal,
        closeSettingsModal,
        dialogPaperSx,
        dialogTitleSx,
        actionButtonSx,
        settingsItemSx,
        smallIconProps,
        compactIconProps,
        saveLogs,
        handleCheckForUpdates,
        advancedUnlocked,
        buildVersion,
        handleBuildVersionTap,
        openModelSettings,
        openSystemPromptSettings,
        isSmall,
        deleteSessionId,
        deleteSessionLabel,
        handleCancelDeleteSession,
        handleConfirmDeleteSession,
        showModelSettings,
        closeModelSettings,
        selectedModelId,
        defaultModelName,
        loadedModelName,
        isTauriRuntime,
        suggestedModels,
        contextLength,
        maxTokens,
        isSavingModel,
        handleSaveModel,
        handleUseDefaultModel,
        showSystemPromptSettings,
        closeSystemPromptSettings,
        systemPrompt,
        handleSaveSystemPrompt,
        handleUseDefaultSystemPrompt,
        chatNotificationOpen,
        setChatNotificationOpen,
        chatNotification,
        modelGateStatus,
        imagePreview,
        closeImagePreview,
    }: ChatDialogsProps) => {
        const openExternalUrl = async (url: string) => {
            if (isTauriRuntime || detectTauriAppRuntime()) {
                try {
                    const { openUrl } =
                        await import("@tauri-apps/plugin-opener");
                    await openUrl(url);
                    return;
                } catch {
                    // fall through to browser open fallback
                }
            }

            if (typeof window !== "undefined") {
                const popup = window.open(url, "_blank", "noopener");
                if (!popup) {
                    window.location.href = url;
                }
            }
        };

        // --- Model settings draft state ---
        const [draftContextLength, setDraftContextLength] = React.useState("");
        const [draftMaxTokens, setDraftMaxTokens] = React.useState("");
        const [draftContextError, setDraftContextError] = React.useState<
            string | null
        >(null);
        const [draftMaxTokensError, setDraftMaxTokensError] = React.useState<
            string | null
        >(null);
        const [showAdvancedLimits, setShowAdvancedLimits] =
            React.useState(false);
        const [draftModelId, setDraftModelId] = React.useState("default");
        const [showBackupComingSoon, setShowBackupComingSoon] =
            React.useState(false);

        // --- System prompt draft state ---
        const [draftSystemPrompt, setDraftSystemPrompt] = React.useState("");

        const modelOptions = React.useMemo(
            () => [
                { id: "default", name: `${defaultModelName} (Default)` },
                ...suggestedModels,
            ],
            [defaultModelName, suggestedModels],
        );

        // Initialize model settings draft from parent state when dialog opens
        React.useEffect(() => {
            if (!showModelSettings) return;
            setDraftModelId(
                modelOptions.some((model) => model.id === selectedModelId)
                    ? selectedModelId
                    : "default",
            );
            setDraftContextLength(contextLength);
            setDraftMaxTokens(maxTokens);
            setDraftContextError(null);
            setDraftMaxTokensError(null);
            setShowAdvancedLimits(!!contextLength || !!maxTokens);
        }, [
            contextLength,
            maxTokens,
            modelOptions,
            selectedModelId,
            showModelSettings,
        ]);

        // Initialize system prompt draft from parent state when dialog opens
        React.useEffect(() => {
            if (!showSystemPromptSettings) return;
            setDraftSystemPrompt(systemPrompt);
        }, [showSystemPromptSettings]); // eslint-disable-line react-hooks/exhaustive-deps

        const validateModelSettings = React.useCallback(() => {
            const contextErrorValue =
                draftContextLength && !/^\d+$/.test(draftContextLength)
                    ? "Enter a number"
                    : undefined;
            const maxTokensErrorValue =
                draftMaxTokens && !/^\d+$/.test(draftMaxTokens)
                    ? "Enter a number"
                    : undefined;

            const contextValue = draftContextLength
                ? Number(draftContextLength)
                : undefined;
            const maxTokensValue = draftMaxTokens
                ? Number(draftMaxTokens)
                : undefined;

            const maxTokensLimitError =
                contextValue && maxTokensValue && maxTokensValue > contextValue
                    ? "Must be <= context length"
                    : undefined;

            setDraftContextError(contextErrorValue ?? null);
            setDraftMaxTokensError(
                maxTokensErrorValue ?? maxTokensLimitError ?? null,
            );

            return !(
                contextErrorValue ||
                maxTokensErrorValue ||
                maxTokensLimitError
            );
        }, [draftContextLength, draftMaxTokens]);

        return (
            <>
                <Dialog
                    open={!!imagePreview}
                    onClose={closeImagePreview}
                    maxWidth={false}
                    fullScreen={isSmall}
                    aria-label={imagePreview?.name || "Image preview"}
                    slotProps={{
                        paper: {
                            sx: {
                                m: 0,
                                width: "100vw",
                                height: "100svh",
                                maxWidth: "none",
                                maxHeight: "none",
                                borderRadius: 0,
                                bgcolor: "rgba(0, 0, 0, 0.94)",
                                boxShadow: "none",
                                overflow: "hidden",
                            },
                        },
                    }}
                >
                    <DialogContent
                        onClick={closeImagePreview}
                        sx={{
                            position: "relative",
                            p: { xs: 2, sm: 3 },
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            overflow: "hidden",
                        }}
                    >
                        {imagePreview && (
                            <Box
                                component="img"
                                src={imagePreview.url}
                                alt={imagePreview.name}
                                onClick={(event) => event.stopPropagation()}
                                sx={{
                                    display: "block",
                                    maxWidth: "100%",
                                    maxHeight: "100%",
                                    objectFit: "contain",
                                    borderRadius: 1,
                                }}
                            />
                        )}
                        <IconButton
                            aria-label="Close image preview"
                            onClick={closeImagePreview}
                            sx={{
                                position: "absolute",
                                top: { xs: 12, sm: 16 },
                                right: { xs: 12, sm: 16 },
                                width: 36,
                                height: 36,
                                color: "common.white",
                                bgcolor: "rgba(0, 0, 0, 0.38)",
                                "&:hover": { bgcolor: "rgba(0, 0, 0, 0.54)" },
                            }}
                        >
                            <HugeiconsIcon
                                icon={Cancel01Icon}
                                {...smallIconProps}
                            />
                        </IconButton>
                    </DialogContent>
                </Dialog>

                <Dialog
                    open={showSettingsModal}
                    onClose={closeSettingsModal}
                    maxWidth="xs"
                    fullWidth
                    slotProps={{
                        paper: {
                            sx: [
                                dialogPaperSx,
                                {
                                    maxHeight:
                                        "min(500px, calc(var(--ensu-viewport-height, 100svh) - 32px))",
                                    display: "flex",
                                    flexDirection: "column",
                                },
                            ],
                        },
                    }}
                >
                    <DialogTitle
                        sx={[
                            dialogTitleSx,
                            {
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "space-between",
                                gap: 1,
                                pr: 1,
                            },
                        ]}
                    >
                        <Box component="span">Settings</Box>
                        <IconButton
                            aria-label="Close settings"
                            onClick={closeSettingsModal}
                            sx={actionButtonSx}
                        >
                            <HugeiconsIcon
                                icon={Cancel01Icon}
                                {...smallIconProps}
                            />
                        </IconButton>
                    </DialogTitle>
                    <DialogContent sx={{ flex: 1, overflowY: "auto" }}>
                        <Stack sx={{ gap: 2 }}>
                            <Stack sx={{ gap: 1 }}>
                                <ListItemButton
                                    onClick={() => {
                                        closeSettingsModal();
                                        void openExternalUrl(
                                            "https://ente.com/blog/ensu/",
                                        );
                                    }}
                                    sx={settingsItemSx}
                                >
                                    <HugeiconsIcon
                                        icon={InformationCircleIcon}
                                        {...compactIconProps}
                                    />
                                    <Typography
                                        variant="small"
                                        sx={{ flex: 1 }}
                                    >
                                        About
                                    </Typography>
                                    <HugeiconsIcon
                                        icon={ArrowRight01Icon}
                                        {...smallIconProps}
                                    />
                                </ListItemButton>

                                {isTauriRuntime && (
                                    <ListItemButton
                                        onClick={() => {
                                            closeSettingsModal();
                                            void handleCheckForUpdates();
                                        }}
                                        sx={settingsItemSx}
                                    >
                                        <HugeiconsIcon
                                            icon={InformationCircleIcon}
                                            {...compactIconProps}
                                        />
                                        <Typography
                                            variant="small"
                                            sx={{ flex: 1 }}
                                        >
                                            Check for updates
                                        </Typography>
                                        <HugeiconsIcon
                                            icon={ArrowRight01Icon}
                                            {...smallIconProps}
                                        />
                                    </ListItemButton>
                                )}

                                <ListItemButton
                                    onClick={() => {
                                        closeSettingsModal();
                                        void saveLogs();
                                    }}
                                    sx={settingsItemSx}
                                >
                                    <HugeiconsIcon
                                        icon={Bug01Icon}
                                        {...compactIconProps}
                                    />
                                    <Typography
                                        variant="small"
                                        sx={{ flex: 1 }}
                                    >
                                        Save logs
                                    </Typography>
                                    <HugeiconsIcon
                                        icon={ArrowRight01Icon}
                                        {...smallIconProps}
                                    />
                                </ListItemButton>

                                <ListItemButton
                                    onClick={() => {
                                        closeSettingsModal();
                                        setShowBackupComingSoon(true);
                                    }}
                                    sx={settingsItemSx}
                                >
                                    <HugeiconsIcon
                                        icon={Upload01Icon}
                                        {...compactIconProps}
                                    />
                                    <Typography
                                        variant="small"
                                        sx={{ flex: 1 }}
                                    >
                                        Sign In to Backup
                                    </Typography>
                                    <HugeiconsIcon
                                        icon={ArrowRight01Icon}
                                        {...smallIconProps}
                                    />
                                </ListItemButton>

                                <ListItemButton
                                    onClick={() => {
                                        closeSettingsModal();
                                        void openExternalUrl(
                                            "https://ente.com/privacy",
                                        );
                                    }}
                                    sx={settingsItemSx}
                                >
                                    <HugeiconsIcon
                                        icon={ViewIcon}
                                        {...compactIconProps}
                                    />
                                    <Typography
                                        variant="small"
                                        sx={{ flex: 1 }}
                                    >
                                        Privacy Policy
                                    </Typography>
                                    <HugeiconsIcon
                                        icon={ArrowRight01Icon}
                                        {...smallIconProps}
                                    />
                                </ListItemButton>

                                <ListItemButton
                                    onClick={() => {
                                        closeSettingsModal();
                                        void openExternalUrl(
                                            "https://ente.com/terms",
                                        );
                                    }}
                                    sx={settingsItemSx}
                                >
                                    <HugeiconsIcon
                                        icon={File01Icon}
                                        {...compactIconProps}
                                    />
                                    <Typography
                                        variant="small"
                                        sx={{ flex: 1 }}
                                    >
                                        Terms of Service
                                    </Typography>
                                    <HugeiconsIcon
                                        icon={ArrowRight01Icon}
                                        {...smallIconProps}
                                    />
                                </ListItemButton>
                            </Stack>

                            {advancedUnlocked && (
                                <Stack sx={{ gap: 1 }}>
                                    <Typography
                                        variant="mini"
                                        sx={{
                                            color: "text.muted",
                                            px: 0.5,
                                            textTransform: "uppercase",
                                            letterSpacing: "0.08em",
                                        }}
                                    >
                                        Advanced
                                    </Typography>

                                    <ListItemButton
                                        onClick={() => {
                                            closeSettingsModal();
                                            openModelSettings();
                                        }}
                                        sx={settingsItemSx}
                                    >
                                        <HugeiconsIcon
                                            icon={Settings01Icon}
                                            {...compactIconProps}
                                        />
                                        <Typography
                                            variant="small"
                                            sx={{ flex: 1 }}
                                        >
                                            Model settings
                                        </Typography>
                                        <HugeiconsIcon
                                            icon={ArrowRight01Icon}
                                            {...smallIconProps}
                                        />
                                    </ListItemButton>

                                    <ListItemButton
                                        onClick={() => {
                                            closeSettingsModal();
                                            openSystemPromptSettings();
                                        }}
                                        sx={settingsItemSx}
                                    >
                                        <HugeiconsIcon
                                            icon={SlidersHorizontalIcon}
                                            {...compactIconProps}
                                        />
                                        <Typography
                                            variant="small"
                                            sx={{ flex: 1 }}
                                        >
                                            System prompt
                                        </Typography>
                                        <HugeiconsIcon
                                            icon={ArrowRight01Icon}
                                            {...smallIconProps}
                                        />
                                    </ListItemButton>
                                </Stack>
                            )}

                            {buildVersion && (
                                <Typography
                                    variant="mini"
                                    onClick={handleBuildVersionTap}
                                    sx={{
                                        color: "text.muted",
                                        textAlign: "center",
                                        cursor: "pointer",
                                        userSelect: "none",
                                        py: 1,
                                    }}
                                >
                                    Build {buildVersion}
                                </Typography>
                            )}
                        </Stack>
                    </DialogContent>
                </Dialog>

                <Dialog
                    open={showBackupComingSoon}
                    onClose={() => setShowBackupComingSoon(false)}
                    fullScreen={isSmall}
                    maxWidth="xs"
                    fullWidth
                    slotProps={{ paper: { sx: dialogPaperSx } }}
                >
                    <DialogTitle sx={dialogTitleSx}>Coming soon</DialogTitle>
                    <DialogContent>
                        <Typography variant="body" sx={{ color: "text.muted" }}>
                            Sign in and cloud backup will be available in a
                            future update.
                        </Typography>
                    </DialogContent>
                    <DialogActions sx={{ px: 3, pb: 3 }}>
                        <Button
                            variant="contained"
                            color="accent"
                            onClick={() => setShowBackupComingSoon(false)}
                        >
                            Got it
                        </Button>
                    </DialogActions>
                </Dialog>

                <Dialog
                    open={Boolean(deleteSessionId)}
                    onClose={handleCancelDeleteSession}
                    fullScreen={isSmall}
                    maxWidth="xs"
                    fullWidth
                    slotProps={{ paper: { sx: dialogPaperSx } }}
                >
                    <DialogTitle sx={dialogTitleSx}>Delete chat?</DialogTitle>
                    <DialogContent>
                        <Typography variant="body" sx={{ color: "text.muted" }}>
                            Delete {deleteSessionLabel}? This cannot be undone.
                        </Typography>
                    </DialogContent>
                    <DialogActions sx={{ px: 3, pb: 3 }}>
                        <Button
                            onClick={handleCancelDeleteSession}
                            color="secondary"
                        >
                            Cancel
                        </Button>
                        <Button
                            variant="contained"
                            color="critical"
                            onClick={() => void handleConfirmDeleteSession()}
                        >
                            Delete
                        </Button>
                    </DialogActions>
                </Dialog>

                {advancedUnlocked && (
                    <Dialog
                        open={showModelSettings}
                        onClose={closeModelSettings}
                        fullScreen={isSmall}
                        maxWidth="sm"
                        fullWidth
                        slotProps={{ paper: { sx: dialogPaperSx } }}
                    >
                        <DialogTitle sx={dialogTitleSx}>
                            Model Settings
                        </DialogTitle>
                        <DialogContent>
                            <Stack sx={{ gap: 3 }}>
                                <Stack sx={{ gap: 1.5 }}>
                                    <Typography
                                        variant="small"
                                        sx={{ color: "text.muted" }}
                                    >
                                        Select model
                                    </Typography>
                                    <TextField
                                        select
                                        fullWidth
                                        label="Model"
                                        value={draftModelId}
                                        onChange={(event) =>
                                            setDraftModelId(event.target.value)
                                        }
                                        helperText={
                                            loadedModelName
                                                ? `Loaded: ${loadedModelName}`
                                                : " "
                                        }
                                    >
                                        {modelOptions.map((model) => (
                                            <MenuItem
                                                key={model.id}
                                                value={model.id}
                                            >
                                                {model.name}
                                            </MenuItem>
                                        ))}
                                    </TextField>
                                </Stack>

                                <Stack sx={{ gap: 1.5 }}>
                                    <Button
                                        onClick={() =>
                                            setShowAdvancedLimits((v) => !v)
                                        }
                                        color="secondary"
                                        sx={{
                                            justifyContent: "flex-start",
                                            px: 0,
                                        }}
                                    >
                                        Advanced limits
                                    </Button>
                                    {!showAdvancedLimits && (
                                        <Typography
                                            variant="mini"
                                            sx={{ color: "text.muted" }}
                                        >
                                            Context length and max output
                                        </Typography>
                                    )}
                                    {showAdvancedLimits && (
                                        <Stack
                                            direction="row"
                                            sx={{ gap: 1.5 }}
                                        >
                                            <TextField
                                                fullWidth
                                                label="Context length"
                                                placeholder="8192"
                                                value={draftContextLength}
                                                onChange={(event) =>
                                                    setDraftContextLength(
                                                        event.target.value,
                                                    )
                                                }
                                                error={!!draftContextError}
                                                helperText={
                                                    draftContextError ?? " "
                                                }
                                            />
                                            <TextField
                                                fullWidth
                                                label="Max output"
                                                placeholder="2048"
                                                value={draftMaxTokens}
                                                onChange={(event) =>
                                                    setDraftMaxTokens(
                                                        event.target.value,
                                                    )
                                                }
                                                error={!!draftMaxTokensError}
                                                helperText={
                                                    draftMaxTokensError ?? " "
                                                }
                                            />
                                        </Stack>
                                    )}
                                    <Typography
                                        variant="mini"
                                        sx={{ color: "text.muted" }}
                                    >
                                        Leave blank to use model defaults
                                    </Typography>
                                </Stack>
                            </Stack>
                        </DialogContent>
                        <DialogActions sx={{ px: 3, pb: 3 }}>
                            <Stack sx={{ width: "100%", gap: 1.5 }}>
                                <Button
                                    variant="contained"
                                    color="accent"
                                    disabled={
                                        isSavingModel ||
                                        modelGateStatus === "downloading"
                                    }
                                    onClick={() => {
                                        if (!validateModelSettings()) return;
                                        handleSaveModel({
                                            modelId:
                                                draftModelId === "default"
                                                    ? ""
                                                    : draftModelId,
                                            contextLength: draftContextLength,
                                            maxTokens: draftMaxTokens,
                                        });
                                    }}
                                >
                                    Save Model Settings
                                </Button>
                                <Button
                                    onClick={handleUseDefaultModel}
                                    color="secondary"
                                >
                                    Reset to defaults
                                </Button>
                                <Typography
                                    variant="mini"
                                    sx={{
                                        color: "text.muted",
                                        textAlign: "center",
                                    }}
                                >
                                    Changes apply the next time the model loads.
                                </Typography>
                            </Stack>
                        </DialogActions>
                    </Dialog>
                )}

                <Dialog
                    open={showSystemPromptSettings}
                    onClose={closeSystemPromptSettings}
                    fullScreen={isSmall}
                    maxWidth="sm"
                    fullWidth
                    slotProps={{ paper: { sx: dialogPaperSx } }}
                >
                    <DialogTitle sx={dialogTitleSx}>System Prompt</DialogTitle>
                    <DialogContent>
                        <Stack sx={{ gap: 2.5 }}>
                            <Typography
                                variant="small"
                                sx={{ color: "text.muted" }}
                            >
                                This prompt is used as-is. Use $date anywhere to
                                insert the current date. Leave blank to use the
                                default prompt.
                            </Typography>
                            <TextField
                                fullWidth
                                multiline
                                minRows={10}
                                maxRows={18}
                                label="Prompt text"
                                placeholder="You are a concise assistant. Current date: $date"
                                value={draftSystemPrompt}
                                onChange={(event) =>
                                    setDraftSystemPrompt(event.target.value)
                                }
                            />
                        </Stack>
                    </DialogContent>
                    <DialogActions sx={{ px: 3, pb: 3 }}>
                        <Stack sx={{ width: "100%", gap: 1.5 }}>
                            <Button
                                variant="contained"
                                color="accent"
                                onClick={() =>
                                    handleSaveSystemPrompt(draftSystemPrompt)
                                }
                            >
                                Save
                            </Button>
                            <Button
                                onClick={handleUseDefaultSystemPrompt}
                                color="secondary"
                            >
                                Use Default Prompt
                            </Button>
                        </Stack>
                    </DialogActions>
                </Dialog>

                <Notification
                    open={chatNotificationOpen}
                    onClose={() => setChatNotificationOpen(false)}
                    attributes={chatNotification}
                    horizontal={isSmall ? "left" : "right"}
                    vertical="bottom"
                    sx={{
                        width: "fit-content",
                        maxWidth: "min(360px, 100vw)",
                        backgroundColor: "transparent",
                        boxShadow: "none",
                        bottom: { xs: 96, md: 24 },
                        "& .MuiButtonBase-root": {
                            padding: "4px 8px",
                            borderRadius: "999px",
                            minHeight: 0,
                            bgcolor: "background.paper",
                            color: "text.base",
                            boxShadow: "none",
                        },
                        "& .MuiStack-root": { gap: 1 },
                        "& .MuiStack-root svg": { fontSize: "18px" },
                        "& .MuiTypography-root": {
                            fontSize: "13px",
                            lineHeight: "18px",
                        },
                        "& .MuiIconButton-root": {
                            padding: 0,
                            bgcolor: "transparent",
                        },
                    }}
                />
            </>
        );
    },
);
