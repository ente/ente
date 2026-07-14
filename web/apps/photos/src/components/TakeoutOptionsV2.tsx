import { FileZipIcon, Folder01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import CloseIcon from "@mui/icons-material/Close";
import { Box, IconButton, Link, Stack, Typography } from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import React from "react";

interface TakeoutOptionsV2Props {
    onBack: () => void;
    onClose: () => void;
    onSelectFolder: () => void;
    onSelectZips: () => void;
}

export function TakeoutOptionsV2({
    onBack,
    onClose,
    onSelectFolder,
    onSelectZips,
}: TakeoutOptionsV2Props): React.JSX.Element {
    return (
        <Stack data-takeout-options-v2 sx={{ gap: "36px", p: "20px" }}>
            <Stack
                direction="row"
                sx={{ alignItems: "center", justifyContent: "space-between" }}
            >
                <Stack direction="row" sx={{ alignItems: "center", gap: 1 }}>
                    <IconButton
                        aria-label="Back"
                        onClick={onBack}
                        sx={{
                            width: "38px",
                            height: "38px",
                            borderRadius: "12px",
                        }}
                    >
                        <ArrowBackIcon sx={{ fontSize: "24px" }} />
                    </IconButton>
                    <Typography
                        sx={{
                            fontFamily: "'Outfit', sans-serif",
                            fontSize: "24px",
                            fontWeight: 600,
                            lineHeight: "32px",
                        }}
                    >
                        Import from Google Photos
                    </Typography>
                </Stack>
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
            </Stack>

            <Stack sx={{ gap: "20px" }}>
                <Stack sx={{ gap: 1 }}>
                    <TakeoutOptionButton
                        icon={<HugeiconsIcon icon={Folder01Icon} size={18} />}
                        label="Unzipped folder"
                        description="Unzip everything into one folder, then select it"
                        onClick={onSelectFolder}
                    />
                    <TakeoutOptionButton
                        icon={<HugeiconsIcon icon={FileZipIcon} size={18} />}
                        label="ZIP files"
                        description="Select your ZIPs, we'll unzip them for you"
                        onClick={onSelectZips}
                    />
                </Stack>
                <Link
                    href="https://ente.com/help/photos/migration/from-google-photos/"
                    target="_blank"
                    rel="noopener"
                    sx={{
                        alignSelf: "center",
                        color: "accent.main",
                        fontSize: "14px",
                        fontWeight: 500,
                        lineHeight: "20px",
                        textDecoration: "underline",
                    }}
                >
                    Need help?
                </Link>
            </Stack>
        </Stack>
    );
}

interface TakeoutOptionButtonProps {
    icon: React.ReactNode;
    label: string;
    description: string;
    onClick: () => void;
}

function TakeoutOptionButton({
    icon,
    label,
    description,
    onClick,
}: TakeoutOptionButtonProps): React.JSX.Element {
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
            </Stack>
        </FocusVisibleButton>
    );
}
