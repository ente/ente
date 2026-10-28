"use client";

import {
    getSpreadLabel,
    getSpreadPageIndices,
    type Spread,
} from "@/lib/spreads";
import { dialogSelectMenuProps, dialogSelectSx } from "@/theme/dialogs";
import { MenuItem, Select } from "@mui/material";
import { ChevronDownIcon } from "./icons";

interface BookPageNavigationProps {
    pageCount: number;
    spreads: Spread[];
    spreadIndex: number;
    disabled: boolean;
    turning: boolean;
    onGoToSpread: (spreadIndex: number) => void;
}

export default function BookPageNavigation({
    pageCount,
    spreads,
    spreadIndex,
    disabled,
    turning,
    onGoToSpread,
}: BookPageNavigationProps) {
    if (pageCount === 0) return null;

    const options = spreads.map((item, index) => {
        const pageIndex = getSpreadPageIndices(item).at(0);
        const label = getSpreadLabel(item, pageCount);
        const isCover = pageIndex === 0 || pageIndex === pageCount - 1;
        return {
            index,
            label:
                pageIndex === undefined
                    ? index < spreads.length / 2
                        ? "Front blanks"
                        : "Back blanks"
                    : isCover
                      ? label
                      : `${label.includes("–") ? "Pages" : "Page"} ${label}`,
        };
    });

    return (
        <Select
            value={Math.min(spreadIndex, spreads.length - 1)}
            disabled={disabled}
            // Lock selection during a turn without flashing MUI's disabled colors.
            readOnly={turning}
            SelectDisplayProps={{ "aria-readonly": turning || undefined }}
            onChange={(event) => onGoToSpread(event.target.value)}
            inputProps={{ "aria-label": "Current page" }}
            IconComponent={ChevronDownIcon}
            MenuProps={dialogSelectMenuProps}
            sx={{
                ...dialogSelectSx,
                width: 136,
                maxWidth: "calc(100vw - 48px)",
                height: 42,
                borderRadius: "14px",
                fontSize: 13,
                "& .MuiSelect-select": { pl: "12px", pr: "32px" },
            }}
        >
            {options.map(({ index, label }) => (
                <MenuItem key={index} value={index}>
                    {label}
                </MenuItem>
            ))}
        </Select>
    );
}
