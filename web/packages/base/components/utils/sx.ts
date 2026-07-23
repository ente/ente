import type { SxProps, Theme } from "@mui/material";
import type { SystemStyleObject } from "@mui/system";

/**
 * Wrapper over Array.isArray that retains the TypeScript type for SxProps when
 * trying to spread them.
 *
 * The recommended pattern to use sx props in our own component (whilst
 * forwarding them to the underlying MUI component) is to:
 *
 *    ...(Array.isArray(sx) ? sx : [sx])
 *
 * However, currently (as of MUI v6), this runs afoul of the
 * 'no-unsafe-assignment' eslint rule. This function provides a workaround, and
 * can be used as a drop-in replacement of Array.isArray in the above pattern.
 *
 * Ref: https://github.com/mui/material-ui/issues/37730
 */
export const isSxArray = (
    sx: SxProps<Theme>,
): sx is readonly (
    | boolean
    | SystemStyleObject<Theme>
    | ((theme: Theme) => SystemStyleObject<Theme>)
)[] => Array.isArray(sx);
