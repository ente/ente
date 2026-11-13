import type { SxProps, Theme } from "@mui/material";
import type { SystemStyleObject } from "@mui/system";

// Array.isArray does not preserve MUI's SxProps array type.
export const isSxArray = (
    sx: SxProps<Theme>,
): sx is readonly (
    | boolean
    | SystemStyleObject<Theme>
    | ((theme: Theme) => SystemStyleObject<Theme>)
)[] => Array.isArray(sx);
