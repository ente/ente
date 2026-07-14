import { Album02Icon, Folder01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import CloseIcon from "@mui/icons-material/Close";
import GoogleIcon from "@mui/icons-material/Google";
import {
    Box,
    CircularProgress,
    IconButton,
    Stack,
    Typography,
} from "@mui/material";
import { SpacedRow } from "ente-base/components/containers";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import React from "react";

interface DefaultOptionsV2Props {
    intent: "import" | "upload";
    isFileSelectionPending: boolean;
    isFolderSelectionPending: boolean;
    onClose: () => void;
    onSelectFiles: () => void;
    onSelectGooglePhotos: () => void;
    onSelectFolder: () => void;
}

export function DefaultOptionsV2({
    intent,
    isFileSelectionPending,
    isFolderSelectionPending,
    onClose,
    onSelectFiles,
    onSelectGooglePhotos,
    onSelectFolder,
}: DefaultOptionsV2Props): React.JSX.Element {
    return (
        <Stack
            data-default-options-v2
            sx={{ gap: intent == "upload" ? "20px" : "36px", p: "20px" }}
        >
            <SpacedRow>
                <Typography
                    sx={{
                        fontFamily: "'Outfit', sans-serif",
                        fontSize: "24px",
                        fontWeight: 600,
                        lineHeight: "32px",
                    }}
                >
                    {intent == "import" ? "Import your library" : "Upload"}
                </Typography>
                <IconButton
                    aria-label="Close"
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
                <ImportOptions {...{ onSelectGooglePhotos }} />
            ) : (
                <UploadOptions
                    {...{
                        isFileSelectionPending,
                        isFolderSelectionPending,
                        onSelectFiles,
                        onSelectGooglePhotos,
                        onSelectFolder,
                    }}
                />
            )}
        </Stack>
    );
}

type ImportOptionsProps = Pick<DefaultOptionsV2Props, "onSelectGooglePhotos">;

function ImportOptions({
    onSelectGooglePhotos,
}: ImportOptionsProps): React.JSX.Element {
    return (
        <Stack direction="row" sx={{ gap: "10px", pb: "12px" }}>
            <ImportProviderButton
                icon={
                    <HugeiconsIcon
                        icon={Album02Icon}
                        size={22}
                        color="var(--mui-palette-text-muted)"
                    />
                }
                label="Google Photos"
                onClick={onSelectGooglePhotos}
            />
        </Stack>
    );
}

type UploadOptionsProps = Pick<
    DefaultOptionsV2Props,
    | "isFileSelectionPending"
    | "isFolderSelectionPending"
    | "onSelectFiles"
    | "onSelectGooglePhotos"
    | "onSelectFolder"
>;

function UploadOptions({
    isFileSelectionPending,
    isFolderSelectionPending,
    onSelectFiles,
    onSelectGooglePhotos,
    onSelectFolder,
}: UploadOptionsProps): React.JSX.Element {
    return (
        <Stack sx={{ gap: "36px" }}>
            <ImportSection title="Upload from">
                <Stack direction="row" sx={{ gap: "10px" }}>
                    <ImportProviderButton
                        icon={
                            <HugeiconsIcon
                                icon={Album02Icon}
                                size={22}
                                color="var(--mui-palette-text-muted)"
                            />
                        }
                        label="Files"
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
                        label="Folder"
                        pending={isFolderSelectionPending}
                        onClick={onSelectFolder}
                    />
                </Stack>
            </ImportSection>

            <ImportSection title="Import from" gap="20px">
                <OptionRowButton
                    icon={
                        <GoogleIcon
                            sx={{ color: "text.muted", fontSize: "20px" }}
                        />
                    }
                    label="Google takeout"
                    onClick={onSelectGooglePhotos}
                />
            </ImportSection>
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
    onClick: () => void;
}

function OptionRowButton({
    icon,
    label,
    description,
    pending,
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
                            fontSize: "14px",
                            fontWeight: 500,
                            lineHeight: "20px",
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
                        <ChevronRightIcon sx={{ fontSize: "18px" }} />
                    )}
                </Box>
            </Stack>
        </FocusVisibleButton>
    );
}

function PendingIndicator(): React.JSX.Element {
    return <CircularProgress size={18} sx={{ color: "stroke.muted" }} />;
}
