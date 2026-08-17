import {
    MenuItem,
    Select,
    type SelectChangeEvent,
    type SxProps,
    type Theme,
    Typography,
} from "@mui/material";
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
        value={selected}
        onChange={(event: SelectChangeEvent) => {
            onSelect(event.target.value as T);
        }}
        variant="outlined"
        displayEmpty
        renderValue={() => {
            const label = options.find((o) => o.value == selected)?.label;
            return label ? (
                <Typography sx={{ whiteSpace: "normal" }}>{label}</Typography>
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
                    sx: { maxWidth: 0 },
                },
                list: {
                    sx: {
                        backgroundColor: "background.paper2",
                        ".MuiMenuItem-root": {
                            color: "text.faint",
                            whiteSpace: "normal",
                        },
                        "&&& > .Mui-selected": { color: "text.base" },
                    },
                },
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
            <MenuItem key={value} value={value}>
                <Typography>{label}</Typography>
            </MenuItem>
        ))}
    </Select>
);
