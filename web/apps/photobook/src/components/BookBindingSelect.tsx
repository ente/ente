import { useBook } from "@/context/book";
import { getBindingPrintSelection, getPrintBinding } from "@/lib/printProducts";
import { accentGreen } from "@/theme/buttons";
import { pageMenuColors } from "@/theme/colors";
import { dialogSelectSx } from "@/theme/dialogs";
import { pageMenuItemSx, pageMenuPaperSx } from "@/theme/menus";
import { MenuItem, Select } from "@mui/material";
import { ChevronDownIcon } from "./icons";

export default function BookBindingSelect({
    disabled = false,
}: {
    disabled?: boolean;
}) {
    const { book, setBook, processingPhotos } = useBook();
    const binding = getPrintBinding(book.printSelection);
    return (
        <Select
            value={binding}
            disabled={disabled || processingPhotos}
            inputProps={{ "aria-label": "Cover type" }}
            IconComponent={ChevronDownIcon}
            MenuProps={{
                sx: {
                    "& .MuiMenuItem-root": {
                        ...pageMenuItemSx,
                        "&.Mui-selected": { bgcolor: "transparent" },
                        "&.Mui-selected:hover, &.Mui-selected.Mui-focusVisible":
                            { bgcolor: pageMenuColors.hover },
                        "&.Mui-selected:active": {
                            bgcolor: pageMenuColors.active,
                        },
                    },
                },
                slotProps: {
                    paper: { sx: pageMenuPaperSx },
                    list: { sx: { p: 0 } },
                },
            }}
            onChange={(event) => {
                const next = event.target.value;
                if (!book.printSelection || next !== binding)
                    setBook((previous) => ({
                        ...previous,
                        printSelection: getBindingPrintSelection(next),
                    }));
            }}
            sx={{
                ...dialogSelectSx,
                bgcolor: "transparent",
                width: "auto",
                mr: "14px",
                height: { xs: 38, sm: 40 },
                "@media (max-width: 959px)": { height: 44, mr: 0 },
                flexShrink: 0,
                borderRadius: { xs: "12px", sm: "14px" },
                fontSize: 13,
                fontWeight: 600,
                "&& .MuiSelect-select.MuiSelect-outlined": {
                    pl: "8px",
                    pr: "28px",
                },
                "& .MuiSelect-icon": {
                    fontSize: 16,
                    right: 8,
                    top: "calc(50% - 8px)",
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
            <MenuItem value="Hardcover" dense disableRipple>
                Hardcover
            </MenuItem>
            <MenuItem value="Softcover" dense disableRipple>
                Softcover
            </MenuItem>
        </Select>
    );
}
