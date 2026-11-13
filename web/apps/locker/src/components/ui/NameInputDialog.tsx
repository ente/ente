import { FormField } from "@/components/ui/FormField";
import { lockerSheetContainerSx, lockerSheetPaperSx } from "@/styles/dialog";
import {
    lockerHeaderIconButtonSx,
    lockerPrimaryButtonSx,
} from "@/styles/fields";
import {
    lockerColorSx,
    lockerTextBodyBoldSx,
    lockerTextH2Sx,
} from "@/styles/tokens";
import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Dialog, IconButton, Stack, Typography } from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { t } from "i18next";

interface NameInputDialogProps {
    open: boolean;
    title: string;
    label: string;
    value: string;
    required?: boolean;
    loading?: boolean;
    disabled: boolean;
    error?: string;
    onChange: (value: string) => void;
    onClose: () => void;
    onSubmit: () => void;
}

export function NameInputDialog({
    open,
    title,
    label,
    value,
    required,
    loading = false,
    disabled,
    error,
    onChange,
    onClose,
    onSubmit,
}: NameInputDialogProps) {
    return (
        <Dialog
            open={open}
            onClose={() => {
                if (!loading) onClose();
            }}
            fullWidth
            maxWidth="xs"
            slotProps={{
                paper: { sx: lockerSheetPaperSx },
                container: { sx: lockerSheetContainerSx },
            }}
        >
            <Box
                component="form"
                onSubmit={(event) => {
                    event.preventDefault();
                    if (open && !loading && !disabled) onSubmit();
                }}
            >
                <Stack
                    direction="row"
                    sx={{ alignItems: "center", gap: 1.5, minHeight: 38 }}
                >
                    <Typography
                        component="h2"
                        sx={{ ...lockerTextH2Sx, flex: 1, minWidth: 0 }}
                    >
                        {title}
                    </Typography>
                    <IconButton
                        aria-label={t("close")}
                        onClick={onClose}
                        disabled={loading}
                        sx={lockerHeaderIconButtonSx}
                    >
                        <HugeiconsIcon
                            icon={Cancel01Icon}
                            size={18}
                            strokeWidth={1.5}
                        />
                    </IconButton>
                </Stack>
                <Box sx={{ mt: 2.5 }}>
                    <FormField
                        autoFocus
                        label={label}
                        value={value}
                        required={required}
                        disabled={loading}
                        onChange={(event) => onChange(event.target.value)}
                        error={open && !!error}
                        helperText={open ? error : undefined}
                    />
                </Box>
                <LoadingButton
                    fullWidth
                    color="primary"
                    type="submit"
                    loading={loading}
                    disabled={disabled}
                    sx={(theme) => ({
                        ...lockerTextBodyBoldSx,
                        mt: 3,
                        borderRadius: "20px",
                        textTransform: "none",
                        ...lockerColorSx(theme, {
                            backgroundColor: "primary",
                            color: "specialWhite",
                        }),
                        "&:hover": {
                            ...lockerColorSx(theme, {
                                backgroundColor: "primaryDark",
                            }),
                        },
                        ...lockerPrimaryButtonSx(theme, { loading }),
                    })}
                >
                    {t("save")}
                </LoadingButton>
            </Box>
        </Dialog>
    );
}
