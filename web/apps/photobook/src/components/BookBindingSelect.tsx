import { useBook } from "@/context/book";
import {
    getBindingPrintSelection,
    getPrintBinding,
    getPrintBindingLabel,
    PRINT_BINDINGS,
    type PrintBinding,
} from "@/lib/printProducts";
import { accentGreen } from "@/theme/buttons";
import { pageMenuColors, toolbarColors, toolbarShadow } from "@/theme/colors";
import { dialogSelectSx } from "@/theme/dialogs";
import { pageMenuItemSx, pageMenuPaperSx } from "@/theme/menus";
import { MenuItem, Select } from "@mui/material";
import { ChevronDownIcon } from "./icons";

export default function BookBindingSelect({
    disabled = false,
}: {
    disabled?: boolean;
}) {
    const { book, setBook, processingPhotos } = useBook(
        "book",
        "setBook",
        "processingPhotos",
    );
    const binding = getPrintBinding(book.printSelection);
    return (
        <Select<PrintBinding | "">
            value={binding ?? ""}
            displayEmpty
            renderValue={(value) => value || "Choose type"}
            disabled={disabled || processingPhotos}
            inputProps={{ "aria-label": "Photobook type" }}
            IconComponent={ChevronDownIcon}
            MenuProps={{
                anchorOrigin: { vertical: "bottom", horizontal: "right" },
                transformOrigin: { vertical: "top", horizontal: "right" },
                sx: {
                    "& .MuiMenuItem-root": {
                        ...pageMenuItemSx,
                        borderRadius: "14px",
                        minHeight: 44,
                        px: "12px",
                        py: "8px",
                        fontSize: 14,
                        lineHeight: "20px",
                        "&.Mui-selected": { bgcolor: "transparent" },
                        "&.Mui-selected:hover, &.Mui-selected.Mui-focusVisible":
                            { bgcolor: pageMenuColors.hover },
                        "&.Mui-selected:active": {
                            bgcolor: pageMenuColors.active,
                        },
                    },
                },
                slotProps: {
                    paper: {
                        sx: {
                            ...pageMenuPaperSx,
                            borderRadius: "20px",
                            p: "6px",
                            boxShadow: toolbarShadow,
                        },
                    },
                    list: { sx: { p: 0 } },
                },
            }}
            onChange={(event) => {
                const next = event.target.value;
                if (next && next !== binding)
                    setBook((previous) => ({
                        ...previous,
                        printSelection: getBindingPrintSelection(next),
                    }));
            }}
            sx={{
                ...dialogSelectSx,
                bgcolor: toolbarColors.control,
                "&:hover": { bgcolor: toolbarColors.hover },
                width: "auto",
                mr: "14px",
                height: { xs: 48, sm: 52 },
                "@media (max-width: 959px)": { mr: 0 },
                flexShrink: 0,
                borderRadius: { xs: "16px", sm: "20px" },
                fontSize: 14,
                fontWeight: 600,
                "&& .MuiSelect-select.MuiSelect-outlined": {
                    pl: "16px",
                    pr: "40px",
                },
                "& .MuiSelect-icon": {
                    fontSize: 20,
                    right: 12,
                    top: "calc(50% - 10px)",
                },
                "& .MuiSelect-select:focus": { bgcolor: "transparent" },
                "&:hover .MuiOutlinedInput-notchedOutline": {
                    borderColor: "transparent",
                },
                "&.Mui-focused .MuiOutlinedInput-notchedOutline": {
                    borderColor: "transparent",
                },
                "&.Mui-disabled .MuiOutlinedInput-notchedOutline": {
                    borderColor: "transparent",
                },
                "& .MuiSelect-select:focus-visible": {
                    outline: `2px solid ${accentGreen}`,
                    outlineOffset: -2,
                    borderRadius: "12px",
                },
            }}
        >
            {PRINT_BINDINGS.map((cover) => (
                <MenuItem key={cover} value={cover} disableRipple>
                    {getPrintBindingLabel(cover)}
                </MenuItem>
            ))}
        </Select>
    );
}
