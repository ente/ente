import {
    LocalizationProvider,
    MobileDateTimePicker,
} from "@mui/x-date-pickers";
import { AdapterDayjs } from "@mui/x-date-pickers/AdapterDayjs";
import dayjs, { Dayjs } from "dayjs";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import type { ParsedMetadataDate } from "ente-media/file-metadata";
import React, { useState } from "react";

interface FileDateTimePickerProps {
    initialValue?: Date;
    onAccept: (date: ParsedMetadataDate) => void;
    onDidClose?: () => void;
}

// The returned offset is the current local offset, not necessarily the photo's.
// Preserve an existing photo offset instead of replacing it with this one.
export const FileDateTimePicker: React.FC<FileDateTimePickerProps> = ({
    initialValue,
    onAccept,
    onDidClose,
}) => {
    const [open, setOpen] = useState(true);
    const [value, setValue] = useState<Dayjs | null>(dayjs(initialValue));

    const isSmallWidth = useIsSmallWidth();

    const handleAccept = (d: Dayjs | null) => {
        if (!dayjs.isDayjs(d))
            throw new Error(`Unexpected non-dayjs result ${typeof d}`);
        onAccept(parseMetadataDateFromDayjs(d));
    };

    const handleClose = () => {
        setOpen(false);
        onDidClose?.();
    };

    return (
        <LocalizationProvider dateAdapter={AdapterDayjs}>
            <MobileDateTimePicker
                value={value}
                onChange={(d) => setValue(d)}
                open={open}
                onClose={handleClose}
                onOpen={() => setOpen(true)}
                disableFuture={true}
                timeSteps={{ minutes: 1 }}
                // Our themed portrait dialog is too tall for larger screens.
                orientation={isSmallWidth ? "portrait" : "landscape"}
                onAccept={handleAccept}
                slots={{ field: EmptyField }}
                slotProps={{
                    // Match the calendar height to prevent a mode-switch jump.
                    layout: {
                        sx: { ".MuiTimeClock-root": { minHeight: "336px" } },
                    },
                }}
            />
        </LocalizationProvider>
    );
};

// The picker is only a dialog; it must not render a closed-state field.
const EmptyField: React.FC = () => <></>;

const parseMetadataDateFromDayjs = (d: Dayjs): ParsedMetadataDate => {
    // Unlike Date.toISOString, this preserves local time and its offset.
    const s = d.format();

    let dateTime: string;
    let offset: string | undefined;

    const m = /Z|[+-]\d\d:?\d\d$/.exec(s);
    if (m?.index) {
        dateTime = s.substring(0, m.index);
        offset = s.substring(m.index);
    } else {
        throw new Error(
            `Dayjs.format returned a string "${s}" without a timezone offset`,
        );
    }

    const timestamp = d.valueOf() * 1000;

    return { dateTime, offset, timestamp };
};
