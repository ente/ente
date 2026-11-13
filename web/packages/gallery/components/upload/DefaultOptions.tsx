import { Album02Icon, Folder01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import AppleIcon from "@mui/icons-material/Apple";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import CloseIcon from "@mui/icons-material/Close";
import GoogleIcon from "@mui/icons-material/Google";
import {
    Box,
    CircularProgress,
    DialogTitle,
    IconButton,
    Link,
    Stack,
    Typography,
} from "@mui/material";
import { SpacedRow } from "ente-base/components/containers";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { t } from "i18next";
import React from "react";
import type { UploadTypeSelectorIntent } from "../Upload";
import { uploadSheetMediaQuery } from "../upload-progress/bottom-sheet";

interface DefaultOptionsBaseProps {
    isFileSelectionPending: boolean;
    isFolderSelectionPending: boolean;
    onClose: () => void;
    onSelectFiles: () => void;
    onSelectFolder: () => void;
}

type DefaultOptionsProps = DefaultOptionsBaseProps &
    (
        | {
              intent: UploadTypeSelectorIntent;
              onSelectApplePhotos?: () => void;
              onSelectGooglePhotos: () => void;
          }
        | {
              intent: "collect";
              onSelectApplePhotos?: never;
              onSelectGooglePhotos?: never;
          }
    );

export function DefaultOptions({
    intent,
    isFileSelectionPending,
    isFolderSelectionPending,
    onClose,
    onSelectApplePhotos,
    onSelectFiles,
    onSelectGooglePhotos,
    onSelectFolder,
}: DefaultOptionsProps): React.JSX.Element {
    const usesUploadSpacing = intent == "upload" || intent == "collect";

    return (
        <Stack
            data-default-options
            sx={{
                gap: usesUploadSpacing ? "20px" : "36px",
                p: "20px",
                pb: usesUploadSpacing ? "28px" : "20px",
                [uploadSheetMediaQuery]: {
                    p: "12px 16px",
                    pb: "calc(28px + env(safe-area-inset-bottom, 0px))",
                    overflowY: "auto",
                },
            }}
        >
            <SpacedRow>
                {intent == "collect" ? (
                    <DialogTitle sx={[{ "&&": { p: 0 } }, optionsTitleSx]}>
                        {t("select_photos")}
                    </DialogTitle>
                ) : (
                    <Typography sx={optionsTitleSx}>
                        {t(intent == "import" ? "import_library" : "upload")}
                    </Typography>
                )}
                <IconButton
                    aria-label={t("close")}
                    onClick={onClose}
                    sx={(theme) => ({
                        width: "38px",
                        height: "38px",
                        backgroundColor: "background.paper",
                        "&:hover": { backgroundColor: "secondary.hover" },
                        ...theme.applyStyles("dark", {
                            backgroundColor: "secondary.main",
                        }),
                    })}
                >
                    <CloseIcon sx={{ fontSize: "18px" }} />
                </IconButton>
            </SpacedRow>

            {intent == "import" ? (
                <ImportOptions
                    {...{
                        isFolderSelectionPending,
                        onSelectApplePhotos,
                        onSelectGooglePhotos,
                        onSelectFolder,
                    }}
                />
            ) : intent == "collect" ? (
                <CollectOptions
                    {...{
                        isFileSelectionPending,
                        isFolderSelectionPending,
                        onSelectFiles,
                        onSelectFolder,
                    }}
                />
            ) : (
                <UploadOptions
                    {...{
                        isFileSelectionPending,
                        isFolderSelectionPending,
                        onSelectApplePhotos,
                        onSelectFiles,
                        onSelectGooglePhotos,
                        onSelectFolder,
                    }}
                />
            )}
        </Stack>
    );
}

type ImportOptionsProps = Pick<
    DefaultOptionsBaseProps,
    "isFolderSelectionPending" | "onSelectFolder"
> & { onSelectApplePhotos?: () => void; onSelectGooglePhotos: () => void };

function ImportOptions({
    isFolderSelectionPending,
    onSelectApplePhotos,
    onSelectGooglePhotos,
    onSelectFolder,
}: ImportOptionsProps): React.JSX.Element {
    return (
        <Stack sx={{ gap: "24px" }}>
            <ImportSection title={t("import_from")}>
                <Stack direction="row" sx={{ gap: "10px" }}>
                    <ImportProviderButton
                        icon={
                            <HugeiconsIcon
                                icon={Album02Icon}
                                size={22}
                                color="var(--mui-palette-text-muted)"
                            />
                        }
                        label={t("google_photos")}
                        onClick={onSelectGooglePhotos}
                    />
                    {onSelectApplePhotos ? (
                        <ImportProviderButton
                            icon={
                                <AppleIcon
                                    sx={{ color: "text.muted", fontSize: 22 }}
                                />
                            }
                            label="Apple Photos"
                            onClick={onSelectApplePhotos}
                        />
                    ) : null}
                </Stack>
            </ImportSection>
            <ImportSection title={t("upload_from")}>
                <Stack direction="row">
                    <ImportProviderButton
                        icon={
                            <HugeiconsIcon
                                icon={Folder01Icon}
                                size={22}
                                color="var(--mui-palette-text-muted)"
                            />
                        }
                        label={t("folder")}
                        pending={isFolderSelectionPending}
                        onClick={onSelectFolder}
                    />
                </Stack>
                <DragAndDropHint />
            </ImportSection>
            <ImportHelp />
        </Stack>
    );
}

type UploadOptionsProps = Pick<
    DefaultOptionsBaseProps,
    | "isFileSelectionPending"
    | "isFolderSelectionPending"
    | "onSelectFiles"
    | "onSelectFolder"
> & { onSelectApplePhotos?: () => void; onSelectGooglePhotos: () => void };

function UploadOptions({
    isFileSelectionPending,
    isFolderSelectionPending,
    onSelectApplePhotos,
    onSelectFiles,
    onSelectGooglePhotos,
    onSelectFolder,
}: UploadOptionsProps): React.JSX.Element {
    return (
        <Stack sx={{ gap: "24px" }}>
            <ImportSection title={t("upload_from")}>
                <Stack direction="row" sx={{ gap: "10px" }}>
                    <ImportProviderButton
                        icon={
                            <HugeiconsIcon
                                icon={Album02Icon}
                                size={22}
                                color="var(--mui-palette-text-muted)"
                            />
                        }
                        label={t("files")}
                        pending={isFileSelectionPending}
                        onClick={onSelectFiles}
                    />
                    <ImportProviderButton
                        icon={
                            <HugeiconsIcon
                                icon={Folder01Icon}
                                size={22}
                                color="var(--mui-palette-text-muted)"
                            />
                        }
                        label={t("folder")}
                        pending={isFolderSelectionPending}
                        onClick={onSelectFolder}
                    />
                </Stack>
                <DragAndDropHint />
            </ImportSection>

            <ImportSection title={t("import_from")} gap="20px">
                <Stack sx={{ gap: 1 }}>
                    <OptionRowButton
                        icon={
                            <GoogleIcon
                                sx={{ color: "text.muted", fontSize: "20px" }}
                            />
                        }
                        label={t("google_takeout")}
                        onClick={onSelectGooglePhotos}
                    />
                    {onSelectApplePhotos ? (
                        <OptionRowButton
                            icon={
                                <AppleIcon
                                    sx={{
                                        color: "text.muted",
                                        fontSize: "20px",
                                    }}
                                />
                            }
                            label="Apple Photos"
                            onClick={onSelectApplePhotos}
                        />
                    ) : null}
                </Stack>
            </ImportSection>
        </Stack>
    );
}

type CollectOptionsProps = Pick<
    DefaultOptionsBaseProps,
    | "isFileSelectionPending"
    | "isFolderSelectionPending"
    | "onSelectFiles"
    | "onSelectFolder"
>;

function CollectOptions({
    isFileSelectionPending,
    isFolderSelectionPending,
    onSelectFiles,
    onSelectFolder,
}: CollectOptionsProps): React.JSX.Element {
    return (
        <Stack sx={{ gap: "16px" }}>
            <Stack sx={{ gap: "10px" }}>
                <OptionRowButton
                    icon={
                        <HugeiconsIcon
                            icon={Album02Icon}
                            size={20}
                            color="var(--mui-palette-text-muted)"
                        />
                    }
                    label={t("files")}
                    pending={isFileSelectionPending}
                    size="large"
                    onClick={onSelectFiles}
                />
                <OptionRowButton
                    icon={
                        <HugeiconsIcon
                            icon={Folder01Icon}
                            size={20}
                            color="var(--mui-palette-text-muted)"
                        />
                    }
                    label={t("folder")}
                    pending={isFolderSelectionPending}
                    size="large"
                    onClick={onSelectFolder}
                />
            </Stack>
            <DragAndDropHint size="large" />
        </Stack>
    );
}

interface ImportSectionProps {
    title: string;
    gap?: string;
    children: React.ReactNode;
}

function ImportSection({
    title,
    gap = "16px",
    children,
}: ImportSectionProps): React.JSX.Element {
    return (
        <Stack sx={{ gap }}>
            <Typography
                sx={{ fontSize: "18px", fontWeight: 600, lineHeight: "24px" }}
            >
                {title}
            </Typography>
            {children}
        </Stack>
    );
}

interface ImportProviderButtonProps {
    icon: React.ReactNode;
    label: string;
    pending?: boolean;
    onClick: () => void;
}

function ImportProviderButton({
    icon,
    label,
    pending,
    onClick,
}: ImportProviderButtonProps): React.JSX.Element {
    return (
        <FocusVisibleButton
            fullWidth
            onClick={onClick}
            sx={(theme) => ({
                flex: 1,
                [uploadSheetMediaQuery]: { flexBasis: "calc(50% - 5px)" },
                minWidth: 0,
                height: "74px",
                p: "12px",
                borderRadius: "16px",
                backgroundColor: "background.paper",
                color: "text.base",
                "&:hover": { backgroundColor: "secondary.hover" },
                ...theme.applyStyles("dark", {
                    backgroundColor: "secondary.main",
                }),
            })}
        >
            <Stack sx={{ alignItems: "center", gap: 1 }}>
                {pending ? <PendingIndicator /> : icon}
                <Typography
                    sx={{
                        fontSize: "14px",
                        fontWeight: 500,
                        lineHeight: "20px",
                    }}
                >
                    {label}
                </Typography>
            </Stack>
        </FocusVisibleButton>
    );
}

interface OptionRowButtonProps {
    icon: React.ReactNode;
    label: string;
    description?: string;
    pending?: boolean;
    size?: "medium" | "large";
    onClick: () => void;
}

function OptionRowButton({
    icon,
    label,
    description,
    pending,
    size = "medium",
    onClick,
}: OptionRowButtonProps): React.JSX.Element {
    return (
        <FocusVisibleButton
            fullWidth
            onClick={onClick}
            sx={(theme) => ({
                height: "60px",
                p: "12px",
                borderRadius: "20px",
                backgroundColor: "background.paper",
                color: "text.base",
                "&:hover": { backgroundColor: "secondary.hover" },
                ...theme.applyStyles("dark", {
                    backgroundColor: "secondary.main",
                }),
            })}
        >
            <Stack
                direction="row"
                sx={{ width: "100%", alignItems: "center", gap: "12px" }}
            >
                <Box
                    sx={{
                        display: "flex",
                        width: "36px",
                        height: "36px",
                        flexShrink: 0,
                        alignItems: "center",
                        justifyContent: "center",
                        color: "text.muted",
                    }}
                >
                    {icon}
                </Box>
                <Stack
                    sx={{ flex: 1, minWidth: 0, textAlign: "left", gap: "4px" }}
                >
                    <Typography
                        sx={{
                            fontSize: size == "large" ? "16px" : "14px",
                            fontWeight: 500,
                            lineHeight: size == "large" ? "24px" : "20px",
                        }}
                    >
                        {label}
                    </Typography>
                    {description && (
                        <Typography
                            sx={{
                                color: "text.muted",
                                fontSize: "12px",
                                fontWeight: 500,
                                lineHeight: "16px",
                            }}
                        >
                            {description}
                        </Typography>
                    )}
                </Stack>
                <Box
                    sx={{
                        display: "flex",
                        width: "48px",
                        height: "36px",
                        flexShrink: 0,
                        alignItems: "center",
                        justifyContent: "center",
                    }}
                >
                    {pending ? (
                        <PendingIndicator />
                    ) : (
                        <ChevronRightIcon
                            sx={{ fontSize: size == "large" ? "20px" : "18px" }}
                        />
                    )}
                </Box>
            </Stack>
        </FocusVisibleButton>
    );
}

function ImportHelp(): React.JSX.Element {
    return (
        <Typography
            sx={{
                color: "text.faint",
                fontSize: "14px",
                fontWeight: 500,
                lineHeight: "20px",
                textAlign: "center",
            }}
        >
            <Link
                href="https://ente.com/help/photos/migration/#import-your-photos-into-ente"
                target="_blank"
                rel="noopener"
                sx={{
                    color: "accent.main",
                    fontWeight: 500,
                    textDecoration: "underline",
                }}
            >
                {t("need_help")}
            </Link>{" "}
            <span style={{ opacity: 0.7 }}>{t("provider_not_listed")}</span>
        </Typography>
    );
}

interface DragAndDropHintProps {
    size?: "medium" | "large";
}

function DragAndDropHint({
    size = "medium",
}: DragAndDropHintProps): React.JSX.Element {
    return (
        <Typography
            sx={{
                color: "text.faint",
                fontSize: size == "large" ? "14px" : "12px",
                fontWeight: 500,
                lineHeight: size == "large" ? "20px" : "16px",
                opacity: 0.7,
                textAlign: "center",
            }}
        >
            {t("drag_and_drop_here")}
        </Typography>
    );
}

function PendingIndicator(): React.JSX.Element {
    return <CircularProgress size={18} sx={{ color: "stroke.muted" }} />;
}

const optionsTitleSx = {
    fontFamily: "'Outfit Variable', sans-serif",
    fontSize: "24px",
    fontWeight: 600,
    lineHeight: "32px",
};
