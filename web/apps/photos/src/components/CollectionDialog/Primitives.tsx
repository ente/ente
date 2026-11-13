import { Search01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import CloseIcon from "@mui/icons-material/Close";
import { InputBase, Stack, styled, type Theme } from "@mui/material";
import { UnstyledButton } from "ente-new/photos/components/UnstyledButton";
import { t } from "i18next";
import React, { useRef } from "react";

export const CollectionDialogSearchField: React.FC<{
    placeholder?: string;
    value: string;
    onChange: (value: string) => void;
}> = ({ value, onChange, placeholder = t("albums_search_hint") }) => {
    const inputRef = useRef<HTMLInputElement>(null);

    const handleClear = () => {
        onChange("");
        inputRef.current?.focus();
    };

    return (
        <Stack direction="row" sx={searchFieldSx}>
            <Stack sx={searchIconSx}>
                <HugeiconsIcon
                    icon={Search01Icon}
                    size={18}
                    color="currentColor"
                />
            </Stack>
            <InputBase
                inputRef={inputRef}
                fullWidth
                autoFocus
                placeholder={placeholder}
                inputProps={{ "aria-label": placeholder }}
                value={value}
                onChange={(e) => onChange(e.target.value)}
                sx={searchInputSx}
                endAdornment={
                    value ? (
                        <CloseIcon
                            fontSize="small"
                            onClick={handleClear}
                            sx={clearIconSx}
                        />
                    ) : undefined
                }
            />
        </Stack>
    );
};

const searchIconSx = (theme: Theme) => ({
    flexShrink: 0,
    color: "rgba(0 0 0 / 0.4)",
    ...theme.applyStyles("dark", { color: "rgba(255 255 255 / 0.4)" }),
});

const searchFieldSx = (theme: Theme) => ({
    alignItems: "center",
    minWidth: 0,
    gap: "12px",
    height: 44,
    borderRadius: "16px",
    backgroundColor: "background.paper",
    px: "16px",
    ...theme.applyStyles("dark", { backgroundColor: "#282828" }),
});

const searchInputSx = {
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    color: "text.base",
    "& input::placeholder": { color: "text.muted", opacity: 1 },
};
const clearIconSx = {
    color: "stroke.muted",
    cursor: "pointer",
    "&:hover": { color: "text.base" },
};

export const CollectionDialogTileButton = styled(UnstyledButton)(
    ({ theme }) => ({
        display: "flex",
        flexDirection: "column",
        alignItems: "flex-start",
        gap: 8,
        minWidth: 0,
        width: "100%",
        textAlign: "left",
        color: theme.vars.palette.text.base,
        borderRadius: 20,
        "&:hover": { opacity: 0.86 },
        "&:focus-visible": {
            outline: `2px solid ${theme.vars.palette.stroke.base}`,
            outlineOffset: 4,
        },
    }),
);

export const CollectionDialogTileCover = styled("div")(({ theme }) => ({
    backgroundColor: theme.vars.palette.background.paper,
    ...theme.applyStyles("dark", {
        backgroundColor: theme.vars.palette.fill.faint,
    }),
    width: "100%",
    aspectRatio: "1",
    flexShrink: 0,
    borderRadius: 20,
    overflow: "hidden",
    position: "relative",
    "& > img": {
        width: "100%",
        height: "100%",
        objectFit: "cover",
        display: "block",
    },
}));
