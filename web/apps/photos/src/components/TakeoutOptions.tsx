import { FileZipIcon, Folder01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    CircularProgress,
    IconButton,
    Link,
    Stack,
    Typography,
} from "@mui/material";
import { isDesktop } from "ente-base/app";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import {
    uploadSheetMediaQuery,
    useIsUploadSheet,
} from "ente-gallery/components/upload-progress/bottom-sheet";
import { t } from "i18next";
import React from "react";

const optionsTitleSx = {
    fontFamily: "'Outfit Variable', sans-serif",
    fontSize: "24px",
    fontWeight: 600,
    lineHeight: "32px",
    [uploadSheetMediaQuery]: { fontFamily: '"Inter Variable", sans-serif' },
};

interface TakeoutOptionsProps {
    provider: "google" | "apple";
    isFolderSelectionPending?: boolean;
    onBack: () => void;
    onClose: () => void;
    onSelectFolder: () => void;
    onSelectZips: () => void;
}

export function TakeoutOptions({
    provider,
    isFolderSelectionPending,
    onBack,
    onClose,
    onSelectFolder,
    onSelectZips,
}: TakeoutOptionsProps): React.JSX.Element {
    const isSheet = useIsUploadSheet();

    return (
        <Stack
            data-takeout-options
            sx={{
                gap: "36px",
                p: "20px",
                [uploadSheetMediaQuery]: {
                    p: "12px 16px",
                    pb: "calc(20px + env(safe-area-inset-bottom, 0px))",
                    overflowY: "auto",
                },
            }}
        >
            <Stack
                direction="row"
                sx={{ alignItems: "center", justifyContent: "space-between" }}
            >
                <Stack direction="row" sx={{ alignItems: "center", gap: 1 }}>
                    <IconButton
                        aria-label={t("go_back")}
                        onClick={onBack}
                        sx={{
                            width: "38px",
                            height: "38px",
                            borderRadius: "12px",
                        }}
                    >
                        <ArrowBackIcon sx={{ fontSize: "24px" }} />
                    </IconButton>
                    <Typography sx={optionsTitleSx}>
                        {provider == "apple"
                            ? isSheet
                                ? "Apple Photos"
                                : "Import from Apple Photos"
                            : t(
                                  isSheet
                                      ? "google_takeout"
                                      : "import_from_google_photos",
                              )}
                    </Typography>
                </Stack>
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
            </Stack>

            <Stack sx={{ gap: "20px" }}>
                <Stack sx={{ gap: 1 }}>
                    <TakeoutOptionButton
                        icon={<HugeiconsIcon icon={Folder01Icon} size={18} />}
                        label={
                            provider == "apple"
                                ? "Exported folder"
                                : t("unzipped_folder")
                        }
                        description={
                            provider == "apple"
                                ? "Select the folder exported from Photos"
                                : t("unzipped_folder_hint")
                        }
                        pending={isFolderSelectionPending}
                        onClick={onSelectFolder}
                    />
                    {provider == "google" && (
                        <TakeoutOptionButton
                            icon={
                                <HugeiconsIcon icon={FileZipIcon} size={18} />
                            }
                            label={t("zip_files")}
                            description={
                                isDesktop
                                    ? t("zip_files_hint")
                                    : t("desktop_only")
                            }
                            disabled={!isDesktop}
                            onClick={onSelectZips}
                        />
                    )}
                </Stack>
                {provider == "apple" && <AppleExportSteps />}
                <Typography
                    sx={{
                        alignSelf: "center",
                        color: "text.faint",
                        fontSize: "14px",
                        fontWeight: 500,
                        lineHeight: "20px",
                    }}
                >
                    <span style={{ opacity: 0.7 }}>
                        {t("takeout_help_prompt")}{" "}
                    </span>
                    <Link
                        href={
                            provider == "apple"
                                ? "https://ente.com/help/photos/faq/migration/#can-i-import-apple-photos-via-desktop"
                                : "https://ente.com/help/photos/migration/from-google-photos/"
                        }
                        target="_blank"
                        rel="noopener"
                        sx={{
                            color: "accent.main",
                            fontWeight: 500,
                            textDecoration: "underline",
                        }}
                    >
                        {t("takeout_help_action")}
                    </Link>
                </Typography>
            </Stack>
        </Stack>
    );
}

function AppleExportSteps(): React.JSX.Element {
    const steps = [
        "In Photos, select your photos and choose File > Export > Export Unmodified Originals",
        "Select Export IPTC as XMP so dates, locations, and captions come along",
    ];

    return (
        <Stack component="ol" sx={{ m: 0, py: 0, pr: 0, pl: "16px" }}>
            {steps.map((step, index) => (
                <Stack
                    component="li"
                    direction="row"
                    key={step}
                    sx={{ gap: "12px", listStyle: "none" }}
                >
                    <Stack sx={{ alignItems: "center" }}>
                        <Box
                            sx={{
                                display: "flex",
                                width: "24px",
                                height: "24px",
                                flexShrink: 0,
                                alignItems: "center",
                                justifyContent: "center",
                                border: "1px solid",
                                borderColor: "stroke.muted",
                                borderRadius: "50%",
                                color: "text.muted",
                                fontSize: "12px",
                                fontWeight: 600,
                                lineHeight: 1,
                            }}
                        >
                            {index + 1}
                        </Box>
                        {index < steps.length - 1 && (
                            <Box
                                sx={{
                                    width: "1px",
                                    minHeight: "16px",
                                    flex: 1,
                                    backgroundColor: "stroke.muted",
                                }}
                            />
                        )}
                    </Stack>
                    <Typography
                        sx={{
                            pb: index < steps.length - 1 ? "16px" : 0,
                            color: "text.muted",
                            fontSize: "13px",
                            fontWeight: 400,
                            lineHeight: "20px",
                        }}
                    >
                        {step}
                    </Typography>
                </Stack>
            ))}
        </Stack>
    );
}

interface TakeoutOptionButtonProps {
    icon: React.ReactNode;
    label: string;
    description: string;
    disabled?: boolean;
    pending?: boolean;
    onClick: () => void;
}

function TakeoutOptionButton({
    icon,
    label,
    description,
    disabled,
    pending,
    onClick,
}: TakeoutOptionButtonProps): React.JSX.Element {
    return (
        <FocusVisibleButton
            fullWidth
            disabled={disabled}
            onClick={onClick}
            sx={(theme) => ({
                minHeight: "60px",
                p: "12px",
                borderRadius: "20px",
                backgroundColor: "background.paper",
                color: "text.base",
                "&:hover": { backgroundColor: "secondary.hover" },
                ...theme.applyStyles("dark", {
                    backgroundColor: "secondary.main",
                }),
                "&.Mui-disabled": {
                    backgroundColor: "secondary.main",
                    color: "text.faint",
                    opacity: 0.55,
                },
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
                    {pending ? (
                        <CircularProgress
                            size={18}
                            sx={{ color: "stroke.muted" }}
                        />
                    ) : (
                        icon
                    )}
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
                </Stack>
                {!disabled && (
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
                        <ChevronRightIcon sx={{ fontSize: "18px" }} />
                    </Box>
                )}
            </Stack>
        </FocusVisibleButton>
    );
}
