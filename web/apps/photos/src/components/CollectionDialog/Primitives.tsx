import AddIcon from "@mui/icons-material/Add";
import CloseIcon from "@mui/icons-material/Close";
import SearchIcon from "@mui/icons-material/Search";
import { InputBase, Stack, styled, type Theme } from "@mui/material";
import { BaseTileButton } from "ente-new/photos/components/Tiles";
import { t } from "i18next";
import React, { useRef } from "react";

export const CollectionDialogSearchField: React.FC<{
    value: string;
    onChange: (value: string) => void;
    placeholder?: string;
    inputRef?: React.RefObject<HTMLInputElement | null>;
}> = ({ value, onChange, placeholder, inputRef: providedInputRef }) => {
    const defaultInputRef = useRef<HTMLInputElement>(null);
    const inputRef = providedInputRef ?? defaultInputRef;

    const handleClear = () => {
        onChange("");
        inputRef.current?.focus();
    };

    return (
        <Stack direction="row" sx={searchFieldSx}>
            <SearchIcon sx={searchIconSx} />
            <InputBase
                inputRef={inputRef}
                fullWidth
                autoFocus
                placeholder={placeholder ?? t("albums_search_hint")}
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
    fontSize: 20,
    flexShrink: 0,
    color: "rgba(0 0 0 / 0.4)",
    ...theme.applyStyles("dark", { color: "rgba(255 255 255 / 0.4)" }),
});

const searchFieldSx = (theme: Theme) => ({
    alignItems: "center",
    gap: "10px",
    height: 44,
    borderRadius: "16px",
    backgroundColor: "background.paper",
    px: "14px",
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

export const CollectionTileButton = styled(BaseTileButton)`
    flex: none;
    width: var(--tile-size, 100%);
    height: auto;
    aspect-ratio: 1;
    border-radius: 16px;
`;

export const CollectionTileTextOverlay = styled("div")`
    position: absolute;
    inset: 0;
    padding: 10px;
    color: #fff;
    background: linear-gradient(
        -10deg,
        rgba(0, 0, 0, 0.1) 0%,
        rgba(0, 0, 0, 0.2) 50%,
        rgba(0, 0, 0, 0.4) 60%,
        rgba(0, 0, 0, 0.6) 100%
    );
`;

export const CreateAlbumTile: React.FC<{ onClick: () => void }> = ({
    onClick,
}) => (
    <CollectionTileButton aria-label={t("new_album")} onClick={onClick}>
        <CreateTileInner>
            <AddIcon />
        </CreateTileInner>
    </CollectionTileButton>
);

const CreateTileInner = styled("span")(({ theme }) => ({
    position: "absolute",
    inset: 0,
    padding: 10,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    border: "1px dashed",
    borderColor: theme.vars.palette.stroke.muted,
    borderRadius: 16,
    color: theme.vars.palette.text.muted,
    "&:hover": { borderColor: "rgba(0 0 0 / 0.45)" },
    ...theme.applyStyles("dark", {
        "&:hover": { borderColor: "rgba(255 255 255 / 0.45)" },
    }),
}));
