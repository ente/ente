export const headerIconSize = 22;
export const headerIconButtonSize = 44;

export const headerIconButtonSx = {
    width: headerIconButtonSize,
    height: headerIconButtonSize,
    p: 0,
    flexShrink: 0,
    "& svg": { width: headerIconSize, height: headerIconSize },
} as const;
