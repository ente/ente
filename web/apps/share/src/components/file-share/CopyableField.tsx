import {
    Copy01Icon,
    ViewIcon,
    ViewOffSlashIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import CheckIcon from "@mui/icons-material/Check";
import { Box, IconButton, Typography } from "@mui/material";
import React, { useState } from "react";

interface CopyableFieldProps {
    label?: string;
    value: string;
    onCopy: (value: string) => void;
    multiline?: boolean;
    maskValue?: boolean;
}

export const CopyableField: React.FC<CopyableFieldProps> = ({
    label,
    value,
    onCopy,
    multiline = false,
    maskValue = false,
}) => {
    const [copied, setCopied] = useState(false);
    const [showValue, setShowValue] = useState(false);

    const handleCopy = () => {
        onCopy(value);
        setCopied(true);
        setTimeout(() => {
            setCopied(false);
        }, 2000);
    };

    return (
        <Box>
            {label && (
                <Typography
                    variant="h6"
                    sx={{
                        fontWeight: 500,
                        fontSize: "16px",
                        color: "text.base",
                        mb: 1,
                        mt: 3,
                    }}
                >
                    {label}
                </Typography>
            )}
            <Box sx={{ position: "relative" }}>
                <Box
                    sx={{
                        px: 4,
                        py: multiline ? 4 : 2,
                        bgcolor: "background.paper",
                        borderRadius: "12px",
                    }}
                >
                    <Typography
                        variant="body"
                        sx={{
                            color: "text.muted",
                            whiteSpace: "pre-wrap",
                            wordBreak: "break-word",
                        }}
                    >
                        {maskValue && !showValue
                            ? "•".repeat(value.length)
                            : value}
                    </Typography>
                </Box>
                <Box
                    sx={{
                        position: "absolute",
                        top: multiline ? 8 : "50%",
                        right: 8,
                        transform: multiline ? "none" : "translateY(-50%)",
                        display: "flex",
                        alignItems: "center",
                        gap: 0.5,
                    }}
                >
                    {maskValue && (
                        <IconButton
                            onClick={() => setShowValue(!showValue)}
                            sx={{
                                color: "text.muted",
                                "&:hover": { bgcolor: "fill.faintHover" },
                            }}
                        >
                            {showValue ? (
                                <HugeiconsIcon
                                    icon={ViewOffSlashIcon}
                                    size={18}
                                />
                            ) : (
                                <HugeiconsIcon icon={ViewIcon} size={18} />
                            )}
                        </IconButton>
                    )}
                    {copied ? (
                        <Box
                            sx={{
                                color: "success.main",
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "center",
                                p: 1,
                            }}
                        >
                            <CheckIcon fontSize="small" />
                        </Box>
                    ) : (
                        <IconButton
                            onClick={handleCopy}
                            sx={{
                                color: "text.muted",
                                "&:hover": { bgcolor: "fill.faintHover" },
                            }}
                        >
                            <HugeiconsIcon icon={Copy01Icon} size={16} />
                        </IconButton>
                    )}
                </Box>
            </Box>
        </Box>
    );
};
