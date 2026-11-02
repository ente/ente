import { matchesSearchCategory } from "@/services/search/search-categories";
import { sidebarSearchOptionsForString } from "@/services/search/sidebar-search-registry";
import { Search01Icon, Settings01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import CloseIcon from "@mui/icons-material/Close";
import { Box, IconButton, InputBase, Stack, Typography } from "@mui/material";
import useAutocomplete from "@mui/material/useAutocomplete";
import type { SidebarActionID } from "ente-new/photos/services/search/types";
import { t } from "i18next";
import { useState, type KeyboardEvent, type ReactNode } from "react";

interface SettingsSearchProps {
    onSelect: (actionID: SidebarActionID) => Promise<void>;
    children: ReactNode;
}

export function SettingsSearch({ onSelect, children }: SettingsSearchProps) {
    const [query, setQuery] = useState("");
    const searching = query.trim().length >= 2;
    const options = sidebarSearchOptionsForString(query).filter((option) =>
        matchesSearchCategory(option, "settings"),
    );
    const {
        getRootProps,
        getInputProps,
        getClearProps,
        getListboxProps,
        getOptionProps,
    } = useAutocomplete({
        options,
        filterOptions: (options) => options,
        getOptionLabel: (option) => option.suggestion.label,
        getOptionKey: (option) =>
            option.suggestion.type === "sidebarAction"
                ? option.suggestion.actionID
                : option.suggestion.label,
        inputValue: query,
        onInputChange: (_, value) => setQuery(value),
        value: null,
        open: searching,
        autoHighlight: true,
        clearOnBlur: false,
        onChange: (_, option) => {
            if (option?.suggestion.type !== "sidebarAction") return;
            setQuery("");
            void onSelect(option.suggestion.actionID);
        },
    });

    return (
        <Box
            sx={{
                display: "flex",
                flexDirection: "column",
                flex: 1,
                minHeight: 0,
            }}
        >
            <Box
                {...getRootProps({
                    onKeyDown: (event: KeyboardEvent<HTMLDivElement>) => {
                        if (event.key === "Escape" && query) {
                            event.stopPropagation();
                            setQuery("");
                        }
                    },
                })}
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    flex: searching ? 1 : "0 0 auto",
                    minHeight: 0,
                    mb: 2,
                }}
            >
                <Stack
                    direction="row"
                    sx={{
                        alignItems: "center",
                        gap: 1,
                        px: 2,
                        height: 52,
                        flexShrink: 0,
                        borderRadius: "16px",
                        bgcolor: "background.paper",
                        "&:focus-within": {
                            boxShadow:
                                "inset 0 0 0 1px var(--mui-palette-text-faint)",
                        },
                    }}
                >
                    <Box
                        sx={{
                            display: "flex",
                            p: 1,
                            color: "text.faint",
                            flexShrink: 0,
                        }}
                    >
                        <HugeiconsIcon
                            icon={Search01Icon}
                            size={18}
                            strokeWidth={1.5}
                        />
                    </Box>
                    <InputBase
                        placeholder={t("search_settings")}
                        inputProps={{
                            ...getInputProps(),
                            "aria-label": t("search_settings"),
                        }}
                        sx={{
                            flex: 1,
                            minWidth: 0,
                            fontSize: "14px",
                            fontWeight: 500,
                            lineHeight: "20px",
                        }}
                    />
                    {query && (
                        <IconButton
                            {...getClearProps()}
                            color="secondary"
                            aria-label={t("clear_search")}
                            size="small"
                            sx={{ mr: -0.75, color: "text.muted" }}
                        >
                            <CloseIcon sx={{ fontSize: 16 }} />
                        </IconButton>
                    )}
                </Stack>
                {searching && (
                    <>
                        <Box
                            component="ul"
                            {...getListboxProps()}
                            aria-label={t("search_settings")}
                            sx={{
                                position: "relative",
                                display: "flex",
                                flexDirection: "column",
                                gap: 0.75,
                                listStyle: "none",
                                p: 0,
                                mb: 0,
                                mt: 2,
                                flex: options.length ? 1 : undefined,
                                minHeight: 0,
                                overflowY: "auto",
                            }}
                        >
                            {options.map((option, index) => {
                                const { key, ...props } = getOptionProps({
                                    option,
                                    index,
                                });
                                const { suggestion } = option;
                                const parentPath =
                                    suggestion.type === "sidebarAction"
                                        ? suggestion.path
                                              .slice(0, -1)
                                              .join(" › ")
                                        : "";
                                return (
                                    <Box
                                        component="li"
                                        key={key}
                                        {...props}
                                        sx={{
                                            display: "flex",
                                            alignItems: "center",
                                            gap: 1.5,
                                            px: 1.5,
                                            py: 1.5,
                                            minHeight: 64,
                                            flexShrink: 0,
                                            boxSizing: "border-box",
                                            borderRadius: "16px",
                                            border: "1px solid",
                                            borderColor: "transparent",
                                            cursor: "pointer",
                                            "&:hover, &.Mui-focused": {
                                                bgcolor: "background.paper",
                                                borderColor: "stroke.muted",
                                            },
                                            "&.Mui-focusVisible": {
                                                borderColor: "text.faint",
                                            },
                                        }}
                                    >
                                        <Box
                                            sx={{
                                                display: "grid",
                                                placeItems: "center",
                                                width: 36,
                                                height: 36,
                                                flexShrink: 0,
                                                borderRadius: "12px",
                                                bgcolor: "fill.muted",
                                                color: "text.muted",
                                            }}
                                        >
                                            <HugeiconsIcon
                                                icon={Settings01Icon}
                                                size={18}
                                                strokeWidth={1.5}
                                            />
                                        </Box>
                                        <Box sx={{ flex: 1, minWidth: 0 }}>
                                            <Typography
                                                variant="body"
                                                sx={{
                                                    display: "block",
                                                    fontWeight: 500,
                                                    lineHeight: "20px",
                                                }}
                                            >
                                                {suggestion.label}
                                            </Typography>
                                            {parentPath && (
                                                <Typography
                                                    variant="small"
                                                    title={parentPath}
                                                    noWrap
                                                    sx={{
                                                        display: "block",
                                                        mt: 0.5,
                                                        color: "text.muted",
                                                    }}
                                                >
                                                    {parentPath}
                                                </Typography>
                                            )}
                                        </Box>
                                        <ChevronRightIcon
                                            sx={{
                                                fontSize: 18,
                                                flexShrink: 0,
                                                color: "text.faint",
                                            }}
                                        />
                                    </Box>
                                );
                            })}
                        </Box>
                        {options.length === 0 && (
                            <Typography
                                role="status"
                                variant="small"
                                sx={{
                                    display: "block",
                                    p: 1.5,
                                    color: "text.muted",
                                }}
                            >
                                {t("no_results")}
                            </Typography>
                        )}
                    </>
                )}
            </Box>
            <Box
                sx={{
                    display: searching ? "none" : "block",
                    flex: 1,
                    minHeight: 0,
                    overflowY: "auto",
                }}
            >
                {children}
            </Box>
        </Box>
    );
}
