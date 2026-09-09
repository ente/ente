import {
    lockerFieldSx,
    lockerPrimaryButtonSx,
} from "@/components/createItemDialog/create-item-dialog-styles";
import { Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Stack, TextField } from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { t } from "i18next";
import React from "react";

export const CreateCollectionRow: React.FC<{
    value: string;
    onChange: (value: string) => void;
    onSubmit: () => void;
    onCancel: () => void;
    loading?: boolean;
    disabled?: boolean;
}> = ({ value, onChange, onSubmit, onCancel, loading = false, disabled }) => (
    <Stack
        direction="row"
        sx={{ gap: "8px", alignItems: "center", mt: "12px" }}
    >
        <TextField
            size="small"
            fullWidth
            autoFocus
            placeholder={t("enterCollectionName")}
            variant="outlined"
            margin="none"
            sx={(theme) => lockerFieldSx(theme, { activeBorder: true })}
            value={value}
            onChange={(e) => onChange(e.target.value)}
            disabled={disabled}
            onKeyDown={(event) => {
                if (event.key === "Escape") {
                    event.preventDefault();
                    event.stopPropagation();
                    onCancel();
                    return;
                }
                if (event.key === "Enter") {
                    event.preventDefault();
                    onSubmit();
                }
            }}
        />
        <LoadingButton
            color="accent"
            loading={loading}
            disabled={!value.trim() || disabled}
            aria-label={t("create")}
            onClick={onSubmit}
            sx={(theme) => ({
                ...lockerPrimaryButtonSx(theme, { loading }),
                minWidth: 0,
                width: 52,
                height: 52,
                p: 0,
                flexShrink: 0,
            })}
        >
            <HugeiconsIcon icon={Tick02Icon} size={20} strokeWidth={1.5} />
        </LoadingButton>
    </Stack>
);
