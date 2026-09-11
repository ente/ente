import { lockerSheetContainerSx, lockerSheetPaperSx } from "@/styles/dialog";
import {
    lockerColorSx,
    lockerTextBodyBoldSx,
    lockerTextBodySx,
    lockerTextH2Sx,
    lockerTextMiniSx,
} from "@/styles/tokens";
import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    Checkbox,
    Dialog,
    FormControlLabel,
    IconButton,
    Stack,
    Typography,
} from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { t } from "i18next";
import React, { useId } from "react";

interface LockerConfirmDialogProps {
    open: boolean;
    illustration: string;
    title: string;
    body: React.ReactNode;
    confirmLabel: string;
    tone?: "critical" | "primary";
    loading?: boolean;
    error?: string;
    checkbox?: {
        label: string;
        checked: boolean;
        onChange: (v: boolean) => void;
    };
    onClose: () => void;
    onConfirm: () => void | Promise<void>;
}

export function LockerConfirmDialog({
    open,
    illustration,
    title,
    body,
    confirmLabel,
    tone = "critical",
    loading,
    error,
    checkbox,
    onClose,
    onConfirm,
}: LockerConfirmDialogProps) {
    const titleID = useId();
    const bodyID = useId();
    const handleClose = () => {
        if (!loading) {
            onClose();
        }
    };

    return (
        <Dialog
            open={open}
            aria-labelledby={titleID}
            aria-describedby={bodyID}
            onClose={handleClose}
            fullWidth
            maxWidth="xs"
            slotProps={{
                paper: { sx: lockerSheetPaperSx },
                container: { sx: lockerSheetContainerSx },
            }}
        >
            <Stack>
                <Box sx={{ display: "flex", justifyContent: "flex-end" }}>
                    <IconButton
                        aria-label={t("cancel")}
                        onClick={handleClose}
                        disabled={loading}
                        sx={(theme) => ({
                            width: 36,
                            height: 36,
                            borderRadius: "50%",
                            padding: 0,
                            ...lockerColorSx(theme, {
                                backgroundColor: "fillLight",
                                color: "iconColor",
                            }),
                            "&:hover": {
                                ...lockerColorSx(theme, {
                                    backgroundColor: "fillHover",
                                }),
                            },
                        })}
                    >
                        <HugeiconsIcon
                            icon={Cancel01Icon}
                            size={18}
                            strokeWidth={1.5}
                        />
                    </IconButton>
                </Box>
                <img
                    src={illustration}
                    alt=""
                    style={{
                        width: 80,
                        height: 80,
                        objectFit: "contain",
                        display: "block",
                        margin: "4px auto 0",
                    }}
                />
                <Typography
                    id={titleID}
                    sx={{ ...lockerTextH2Sx, textAlign: "center", mt: 2.5 }}
                >
                    {title}
                </Typography>
                <Typography
                    id={bodyID}
                    sx={(theme) => ({
                        ...lockerTextBodySx,
                        textAlign: "center",
                        mt: 1.5,
                        ...lockerColorSx(theme, { color: "textLight" }),
                    })}
                >
                    {body}
                </Typography>
                {checkbox && (
                    <Box
                        sx={{
                            display: "flex",
                            mt: 2.5,
                            justifyContent: "center",
                        }}
                    >
                        <FormControlLabel
                            control={
                                <Checkbox
                                    checked={checkbox.checked}
                                    disabled={loading}
                                    onChange={(event) =>
                                        checkbox.onChange(event.target.checked)
                                    }
                                />
                            }
                            label={checkbox.label}
                            sx={{
                                alignItems: "center",
                                m: 0,
                                "& .MuiFormControlLabel-label":
                                    lockerTextBodySx,
                            }}
                        />
                    </Box>
                )}
                {error && (
                    <Typography
                        sx={(theme) => ({
                            ...lockerTextMiniSx,
                            textAlign: "center",
                            mt: 1.5,
                            ...lockerColorSx(theme, { color: "warning" }),
                        })}
                    >
                        {error}
                    </Typography>
                )}
                <LoadingButton
                    fullWidth
                    color={tone}
                    loading={loading}
                    onClick={onConfirm}
                    sx={(theme) => ({
                        ...lockerTextBodyBoldSx,
                        mt: 3,
                        minHeight: 52,
                        borderRadius: "20px",
                        textTransform: "none",
                        ...lockerColorSx(theme, {
                            backgroundColor:
                                tone === "critical" ? "warning" : "primary",
                            color: "specialWhite",
                        }),
                        "&:hover": {
                            ...lockerColorSx(theme, {
                                backgroundColor:
                                    tone === "critical"
                                        ? "warningDark"
                                        : "primaryDark",
                            }),
                        },
                        "&.Mui-disabled": {
                            ...lockerColorSx(theme, {
                                backgroundColor:
                                    tone === "critical" ? "warning" : "primary",
                                color: "specialWhite",
                            }),
                        },
                    })}
                >
                    {confirmLabel}
                </LoadingButton>
            </Stack>
        </Dialog>
    );
}
