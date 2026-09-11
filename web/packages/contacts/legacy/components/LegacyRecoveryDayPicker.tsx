import {
    Stack,
    ToggleButton,
    ToggleButtonGroup,
    type SxProps,
    type Theme,
} from "@mui/material";
import { isSxArray } from "ente-base/components/utils/sx";
import React from "react";

export const legacyRecoveryDayOptions = [7, 14, 30] as const;

interface LegacyRecoveryDayPickerProps {
    selectedDays: number;
    onChange: (days: number) => void;
    sx?: SxProps<Theme>;
}

export const LegacyRecoveryDayPicker: React.FC<
    LegacyRecoveryDayPickerProps
> = ({ selectedDays, onChange, sx }) => (
    <ToggleButtonGroup
        exclusive
        value={selectedDays}
        onChange={(_, value: number | null) => value && onChange(value)}
        fullWidth
        sx={[
            {
                gap: 1,
                "& .MuiToggleButton-root": {
                    flex: 1,
                    px: 1.5,
                    py: 1.25,
                    border: 0,
                    borderRadius: "16px !important",
                    minHeight: 44,
                    textTransform: "none",
                    fontWeight: 600,
                    color: "text.muted",
                    backgroundColor: "fill.faint",
                },
                "& .MuiToggleButton-root.Mui-selected": {
                    color: "accent.contrastText",
                    backgroundColor: "accent.main",
                },
                "& .MuiToggleButton-root:hover": {
                    backgroundColor: "fill.muted",
                },
                "& .MuiToggleButton-root.Mui-selected:hover": {
                    backgroundColor: "accent.main",
                },
            },
            ...(sx ? (isSxArray(sx) ? sx : [sx]) : []),
        ]}
    >
        {legacyRecoveryDayOptions.map((days) => (
            <ToggleButton key={days} value={days}>
                <Stack sx={{ alignItems: "center" }}>{days} days</Stack>
            </ToggleButton>
        ))}
    </ToggleButtonGroup>
);
