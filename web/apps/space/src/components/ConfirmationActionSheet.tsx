import { Box, Dialog, useMediaQuery } from "@mui/material";
import {
    SpaceActionFeedbackIcon,
    type SpaceActionPhase,
} from "components/SpaceActionFeedback";
import { SpaceBottomSheetTransition } from "components/SpaceBottomSheetTransition";
import React from "react";

const green = "#08C225";
const dangerColor = "#F63A3A";
const textBase = "#000";

interface ConfirmationActionSheetProps {
    appearance?: "light" | "dark";
    open: boolean;
    title: string;
    description?: React.ReactNode;
    confirmLabel: string;
    confirmBackgroundColor?: string;
    confirmActionPhase?: SpaceActionPhase | null;
    confirmDisabled?: boolean;
    errorMessage?: string | null;
    cancelLabel?: string;
    cancelDisabled?: boolean;
    onCancel: () => void;
    onConfirm: () => void;
    onExited?: () => void;
}

export const ConfirmationActionSheet: React.FC<
    ConfirmationActionSheetProps
> = ({
    appearance = "light",
    open,
    title,
    description,
    confirmLabel,
    confirmBackgroundColor = dangerColor,
    confirmActionPhase = null,
    confirmDisabled = false,
    errorMessage = null,
    cancelLabel = "Cancel",
    cancelDisabled = false,
    onCancel,
    onConfirm,
    onExited,
}) => {
    const titleID = React.useId();
    const isDark = appearance == "dark";
    const isBottomSheet = useMediaQuery("(max-width: 599px)");

    return (
        <Dialog
            open={open}
            onClose={confirmActionPhase ? undefined : onCancel}
            maxWidth={false}
            aria-labelledby={titleID}
            slots={
                isBottomSheet
                    ? { transition: SpaceBottomSheetTransition }
                    : undefined
            }
            sx={
                isDark
                    ? {
                          zIndex: 1500,
                          "& .MuiBackdrop-root": {
                              backgroundColor: "rgba(0, 0, 0, 0.86) !important",
                          },
                      }
                    : undefined
            }
            slotProps={{
                backdrop: {
                    sx: {
                        backgroundColor: isDark
                            ? "rgba(0, 0, 0, 0.86)"
                            : "rgba(0, 0, 0, 0.48)",
                    },
                },
                paper: {
                    sx: {
                        bgcolor: isDark ? "#1E1E1E" : "#FAFAFA",
                        borderRadius: "28px 28px 0 0",
                        bottom: 0,
                        boxShadow: "none",
                        boxSizing: "border-box",
                        left: 0,
                        m: 0,
                        maxWidth: "none",
                        p: "26px 20px 24px",
                        position: "fixed",
                        width: "100vw",
                        "@media (min-width: 600px)": {
                            borderRadius: "20px",
                            bottom: "auto",
                            left: "50%",
                            maxWidth: 363,
                            top: "50%",
                            transform: "translate(-50%, -50%)",
                            width: 363,
                        },
                    },
                },
                transition: { onExited },
            }}
        >
            <Box
                sx={{
                    maxWidth: 320,
                    mx: "auto",
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: "none" },
                }}
            >
                <Box
                    component="h2"
                    id={titleID}
                    sx={{
                        color: isDark ? "#F4F4F4" : textBase,
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 15,
                        fontWeight: 600,
                        lineHeight: "20px",
                        m: 0,
                        px: "20px",
                        textAlign: "center",
                    }}
                >
                    {title}
                </Box>
                {description && (
                    <Box
                        sx={{
                            color: isDark ? "#BDBDBD" : "#666666",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 13,
                            lineHeight: "18px",
                            mt: "8px",
                            px: "20px",
                            textAlign: "center",
                        }}
                    >
                        {description}
                    </Box>
                )}
                <Box
                    sx={{
                        display: "flex",
                        flexDirection: "column",
                        gap: "12px",
                        mt: description ? "20px" : "28px",
                    }}
                >
                    <SheetButton
                        label={confirmLabel}
                        backgroundColor={confirmBackgroundColor}
                        color="#FFFFFF"
                        disabled={confirmDisabled}
                        actionPhase={confirmActionPhase}
                        onClick={onConfirm}
                    />
                    <SheetButton
                        label={cancelLabel}
                        backgroundColor={isDark ? "#333333" : "#F2F2F2"}
                        color={isDark ? "#D8D8D8" : "#666666"}
                        disabled={cancelDisabled}
                        onClick={onCancel}
                    />
                    {errorMessage && (
                        <Box
                            role="alert"
                            sx={{
                                color: dangerColor,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 13,
                                fontWeight: 600,
                                lineHeight: "18px",
                                px: "12px",
                                textAlign: "center",
                            }}
                        >
                            {errorMessage}
                        </Box>
                    )}
                </Box>
            </Box>
        </Dialog>
    );
};

interface SheetButtonProps {
    backgroundColor: string;
    color: string;
    actionPhase?: SpaceActionPhase | null;
    disabled?: boolean;
    label: string;
    onClick: () => void;
}

const SheetButton: React.FC<SheetButtonProps> = ({
    backgroundColor,
    color,
    actionPhase = null,
    disabled = false,
    label,
    onClick,
}) => (
    <Box
        component="button"
        type="button"
        aria-label={label}
        disabled={disabled}
        onClick={onClick}
        sx={{
            alignItems: "center",
            bgcolor: backgroundColor,
            border: 0,
            borderRadius: "20px",
            color,
            cursor: disabled ? "default" : "pointer",
            display: "flex",
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 14,
            fontWeight: 600,
            height: 48,
            justifyContent: "center",
            lineHeight: "20px",
            px: "24px",
            py: "14px",
            transition: "filter 120ms ease, opacity 120ms ease",
            width: "100%",
            "&:active": disabled ? undefined : { filter: "brightness(0.96)" },
            "&:disabled": { opacity: 1 },
            "&:focus-visible": {
                outline: `2px solid ${green}`,
                outlineOffset: 2,
            },
            "&:hover": disabled ? undefined : { filter: "brightness(0.98)" },
        }}
    >
        {actionPhase ? <SpaceActionFeedbackIcon phase={actionPhase} /> : label}
    </Box>
);
