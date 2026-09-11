import {
    Moon02Icon,
    SmartPhone01Icon,
    Sun03Icon,
    Tick02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, FormControlLabel, Radio, RadioGroup } from "@mui/material";
import { useColorScheme } from "@mui/material/styles";
import { t } from "i18next";
import type { ChangeEvent } from "react";
import {
    LockerTitledNestedSidebarDrawer,
    type LockerNestedSidebarDrawerVisibilityProps,
} from "./LockerSidebarShell";
import {
    bodySx,
    rowSurfaceSx,
    textBaseSx,
    textLightSx,
} from "./locker-sidebar-styles";

const themeOptions = [
    { value: "system", icon: SmartPhone01Icon },
    { value: "light", icon: Sun03Icon },
    { value: "dark", icon: Moon02Icon },
] as const;

export function LockerThemeDrawer({
    open,
    onClose,
    onRootClose,
}: LockerNestedSidebarDrawerVisibilityProps) {
    const { mode, setMode } = useColorScheme();

    function handleChange(
        _event: ChangeEvent<HTMLInputElement>,
        value: string,
    ) {
        if (value === "system" || value === "light" || value === "dark") {
            setMode(value);
        }
    }

    return (
        <LockerTitledNestedSidebarDrawer
            {...{ open, onClose, onRootClose }}
            title={t("theme")}
        >
            {mode && (
                <RadioGroup
                    aria-label={t("theme")}
                    value={mode}
                    onChange={handleChange}
                    sx={{ borderRadius: "20px", overflow: "hidden" }}
                >
                    {themeOptions.map(({ value, icon }) => (
                        <FormControlLabel
                            key={value}
                            value={value}
                            label={
                                <Box
                                    sx={{
                                        display: "flex",
                                        alignItems: "center",
                                        gap: 1.5,
                                    }}
                                >
                                    <Box
                                        sx={[
                                            textLightSx,
                                            {
                                                width: 36,
                                                height: 36,
                                                display: "grid",
                                                placeItems: "center",
                                                flexShrink: 0,
                                            },
                                        ]}
                                    >
                                        <HugeiconsIcon
                                            icon={icon}
                                            size={18}
                                            strokeWidth={1.6}
                                        />
                                    </Box>
                                    {t(value)}
                                </Box>
                            }
                            labelPlacement="start"
                            control={
                                <Radio
                                    icon={
                                        <Box sx={{ width: 24, height: 24 }} />
                                    }
                                    checkedIcon={
                                        <HugeiconsIcon
                                            icon={Tick02Icon}
                                            size={24}
                                            strokeWidth={1.6}
                                        />
                                    }
                                    sx={{
                                        p: "6px",
                                        "&.Mui-checked": {
                                            color: "accent.main",
                                        },
                                    }}
                                />
                            }
                            sx={[
                                rowSurfaceSx,
                                textBaseSx,
                                {
                                    m: 0,
                                    p: "9px 12px",
                                    minHeight: 54,
                                    boxSizing: "border-box",
                                    position: "relative",
                                    justifyContent: "space-between",
                                    "& .MuiFormControlLabel-label": bodySx,
                                    "&:not(:last-child)::after": {
                                        content: '""',
                                        position: "absolute",
                                        bottom: 0,
                                        left: 60,
                                        right: 0,
                                        borderBottom: "1px solid",
                                        borderColor: "divider",
                                        opacity: 0.5,
                                    },
                                    "&:has(.Mui-focusVisible)": {
                                        outline: "2px solid",
                                        outlineColor: "accent.main",
                                        outlineOffset: -2,
                                    },
                                },
                            ]}
                        />
                    ))}
                </RadioGroup>
            )}
        </LockerTitledNestedSidebarDrawer>
    );
}
