import {
    Select,
    type SelectChangeEvent,
    type SxProps,
    type Theme,
    Typography,
} from "@mui/material";
import { ContextMenuItem } from "ente-base/components/ContextMenu";
import { contextMenuPaperStyles } from "ente-base/components/ContextMenu.styles";
import { isSxArray } from "ente-base/components/utils/sx";

export interface DropdownOption<T> {
    label: string;
    value: T;
}

interface DropdownInputProps<T> {
    options: DropdownOption<T>[];
    selected: T | undefined;
    onSelect: (selectedValue: T) => void;
    placeholder?: string;
    sx?: SxProps<Theme>;
}

export const DropdownInput = <T extends string>({
    options,
    selected,
    onSelect,
    placeholder,
    sx,
}: DropdownInputProps<T>) => (
    <Select
        value={selected ?? ""}
        onChange={(event: SelectChangeEvent) => {
            onSelect(event.target.value as T);
        }}
        variant="outlined"
        displayEmpty
        renderValue={() => {
            const label = options.find((o) => o.value == selected)?.label;
            return label ? (
                <Typography
                    sx={{
                        whiteSpace: "normal",
                        fontSize: "13px",
                        fontWeight: 500,
                    }}
                >
                    {label}
                </Typography>
            ) : (
                <Typography sx={{ color: "text.muted" }}>
                    {placeholder}
                </Typography>
            );
        }}
        MenuProps={{
            slotProps: {
                paper: {
                    // MUI's item min-width prevents wrapping unless max-width is reset.
                    sx: (theme) => ({
                        ...contextMenuPaperStyles(theme),
                        maxWidth: 0,
                    }),
                },
                list: { sx: { p: 1 } },
            },
        }}
        sx={[
            {
                ".MuiOutlinedInput-notchedOutline": {
                    borderColor: "transparent",
                },
                ".MuiSelect-select": { backgroundColor: "fill.faint" },
            },
            ...(sx ? (isSxArray(sx) ? sx : [sx]) : []),
        ]}
    >
        {options.map(({ value, label }) => (
            <ContextMenuItem
                key={value}
                value={value}
                sx={{ whiteSpace: "normal" }}
            >
                {label}
            </ContextMenuItem>
        ))}
    </Select>
);
