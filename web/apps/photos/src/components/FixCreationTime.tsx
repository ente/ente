import {
    AlertCircleIcon,
    Cancel01Icon,
    Tick02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    Dialog,
    FormControlLabel,
    IconButton,
    LinearProgress,
    Link,
    Radio,
    RadioGroup,
    Stack,
    Typography,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import {
    v2CloseButtonSx,
    v2HeaderRowSx,
    v2PaperSx,
    v2SubmitButtonSx,
} from "ente-base/components/SingleInput.styles";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import log from "ente-base/log";
import { downloadManager } from "ente-gallery/services/download";
import { extractExifDates } from "ente-gallery/services/exif";
import { tryParseEpochMicrosecondsFromFileName } from "ente-gallery/services/upload/date";
import { fileLogID, type EnteFile } from "ente-media/file";
import {
    fileCreationPhotoDate,
    fileFileName,
    type ParsedMetadataDate,
} from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { FileDateTimePicker } from "ente-new/photos/components/FileDateTimePicker";
import { updateFilePublicMagicMetadata } from "ente-new/photos/services/file";
import { useFormik } from "formik";
import { t } from "i18next";
import React, { useEffect, useState } from "react";

type FixCreationTimeProps = ModalVisibilityProps & {
    files: EnteFile[];
    onRemotePull: () => Promise<void>;
};

export const FixCreationTime: React.FC<FixCreationTimeProps> = ({
    open,
    onClose,
    files,
    onRemotePull,
}) => {
    const [step, setStep] = useState<Step | undefined>();
    const [progress, setProgress] = useState({ completed: 0, total: 0 });

    useEffect(() => {
        if (open) setStep(undefined);
    }, [open]);

    const onSubmit = async (values: FormValues) => {
        setStep("running");
        const completedWithErrors = await updateFiles(
            files,
            values.option,
            values.customDate,
            setProgress,
        );
        setStep(completedWithErrors ? "completed-with-errors" : "completed");
        await onRemotePull();
    };

    const message = messageForStatus(step);

    return (
        <Dialog
            open={open}
            onClose={(_, reason) => {
                if (reason == "backdropClick" || step == "running") return;
                onClose();
            }}
            maxWidth={false}
            aria-labelledby="fix-date-time-title"
            aria-describedby="fix-date-time-description"
            aria-busy={step == "running"}
            slotProps={{
                paper: {
                    sx: [
                        v2PaperSx,
                        {
                            width: 560,
                            maxWidth: "calc(100% - 32px)",
                            boxSizing: "border-box",
                            m: "16px",
                            p: "19px",
                        },
                    ],
                },
            }}
        >
            <Stack sx={{ gap: "18px" }}>
                <Stack direction="row" sx={v2HeaderRowSx}>
                    <Typography
                        id="fix-date-time-title"
                        component="h2"
                        sx={{
                            fontSize: 20,
                            lineHeight: "28px",
                            fontWeight: 600,
                        }}
                    >
                        {step == "running"
                            ? t("fix_creation_time_in_progress")
                            : t("fix_creation_time")}
                    </Typography>
                    <IconButton
                        aria-label={t("close")}
                        onClick={onClose}
                        disabled={step == "running"}
                        sx={v2CloseButtonSx}
                    >
                        <HugeiconsIcon icon={Cancel01Icon} size={18} />
                    </IconButton>
                </Stack>
                <Typography
                    id="fix-date-time-description"
                    sx={{
                        fontSize: 13,
                        lineHeight: "19px",
                        color: "text.muted",
                        fontWeight: 400,
                    }}
                    role={step == "completed" ? "status" : undefined}
                >
                    {(step == "completed-with-errors" ? undefined : message) ??
                        (step == "running"
                            ? t("fix_creation_time_in_progress")
                            : t("fix_creation_time_options"))}
                </Typography>
                {step == "running" && <Progress {...progress} />}
                <OptionsForm {...{ step, files, onSubmit, onClose }} />
            </Stack>
        </Dialog>
    );
};

type Step = "running" | "completed" | "completed-with-errors";

type FixOption =
    | "date-time-original"
    | "date-time-digitized"
    | "metadata-date"
    | "file-name"
    | "custom";

interface FormValues {
    option: FixOption;
    customDate: ParsedMetadataDate | undefined;
}

interface FixProgress {
    completed: number;
    total: number;
}

const messageForStatus = (step?: Step) => {
    switch (step) {
        case undefined:
        case "running":
            return undefined;
        case "completed":
            return t("fix_creation_time_completed");
        case "completed-with-errors":
            return t("fix_creation_time_completed_with_errors");
    }
};

const Progress: React.FC<FixProgress> = ({ completed, total }) => (
    <Stack sx={{ gap: 2 }}>
        <Typography role="status" sx={{ textAlign: "center" }}>
            {completed} / {total} · {t("fix_creation_time_file_updated")}
        </Typography>
        <LinearProgress
            variant="determinate"
            value={total ? Math.round((completed * 100) / total) : 0}
        />
    </Stack>
);

interface OptionsFormProps {
    step: Step | undefined;
    files: EnteFile[];
    onSubmit: (values: FormValues) => Promise<void>;
    onClose: () => void;
}

const OptionsForm: React.FC<OptionsFormProps> = ({
    step,
    files,
    onSubmit,
    onClose,
}) => {
    const [showPicker, setShowPicker] = useState(false);
    const { values, handleChange, setValues, handleSubmit } =
        useFormik<FormValues>({
            initialValues: {
                option: "date-time-original",
                customDate: undefined,
            },
            validateOnBlur: false,
            onSubmit,
        });

    const options: { value: FixOption; label: string }[] = [
        { value: "date-time-original", label: t("exif_date_time_original") },
        { value: "date-time-digitized", label: t("exif_date_time_digitized") },
        { value: "metadata-date", label: t("exif_metadata_date") },
        { value: "file-name", label: t("file_name") },
        { value: "custom", label: t("custom_time") },
    ];

    if (step == "running") return null;
    if (step == "completed")
        return (
            <FocusVisibleButton fullWidth onClick={onClose} sx={submitButtonSx}>
                {t("close")}
            </FocusVisibleButton>
        );

    return (
        <Stack component="form" onSubmit={handleSubmit} sx={{ gap: "18px" }}>
            <RadioGroup
                name="option"
                value={values.option}
                onChange={(event, option) => {
                    handleChange(event);
                    if (option == "custom") setShowPicker(true);
                }}
                aria-labelledby="fix-date-time-description"
                aria-describedby={
                    step == "completed-with-errors"
                        ? "fix-date-time-error"
                        : undefined
                }
                sx={{ gap: "8px" }}
            >
                {options.map(({ value, label }) => (
                    <FormControlLabel
                        key={value}
                        value={value}
                        labelPlacement="start"
                        onClick={
                            value == "custom"
                                ? () => setShowPicker(true)
                                : undefined
                        }
                        control={
                            <Radio
                                disableRipple
                                icon={<Box sx={{ width: 34, height: 34 }} />}
                                checkedIcon={
                                    <Box
                                        sx={{
                                            width: 34,
                                            height: 34,
                                            display: "grid",
                                            placeItems: "center",
                                        }}
                                    >
                                        <Box
                                            sx={{
                                                width: 18,
                                                height: 18,
                                                borderRadius: "50%",
                                                bgcolor: "accent.main",
                                                color: "white",
                                                display: "grid",
                                                placeItems: "center",
                                            }}
                                        >
                                            <HugeiconsIcon
                                                icon={Tick02Icon}
                                                size={12}
                                            />
                                        </Box>
                                    </Box>
                                }
                                sx={{
                                    p: 0,
                                    ml: "12px",
                                    "&.Mui-focusVisible": {
                                        outline: "2px solid",
                                        outlineColor: "accent.main",
                                        borderRadius: "12px",
                                    },
                                }}
                            />
                        }
                        label={
                            <Typography
                                sx={{
                                    fontSize: 14,
                                    lineHeight: "20px",
                                    fontWeight: 500,
                                }}
                            >
                                {label}
                            </Typography>
                        }
                        sx={(theme) => ({
                            m: 0,
                            minHeight: 60,
                            boxSizing: "border-box",
                            pl: "15px",
                            pr: "11px",
                            py: "9px",
                            border: "1px solid",
                            borderColor:
                                values.option == value
                                    ? "#e0e0e0"
                                    : "transparent",
                            borderRadius: "20px",
                            backgroundColor: "background.paper",
                            justifyContent: "space-between",
                            "& .MuiFormControlLabel-label": {
                                flex: 1,
                                minWidth: 0,
                            },
                            "&:hover": { backgroundColor: "fill.faintHover" },
                            "&:has(.Mui-focusVisible)": {
                                outline: "2px solid",
                                outlineColor: "accent.main",
                                outlineOffset: 2,
                            },
                            ...theme.applyStyles("dark", {
                                borderColor:
                                    values.option == value
                                        ? "stroke.muted"
                                        : "transparent",
                                backgroundColor: "#252525",
                            }),
                        })}
                    />
                ))}
            </RadioGroup>
            {showPicker && (
                <FileDateTimePicker
                    initialValue={
                        values.customDate
                            ? new Date(values.customDate.timestamp / 1000)
                            : undefined
                    }
                    onAccept={(customDate) => {
                        void setValues({ option: "custom", customDate });
                    }}
                    onDidClose={() => setShowPicker(false)}
                />
            )}
            {step == "completed-with-errors" && (
                <Stack
                    id="fix-date-time-error"
                    role="alert"
                    direction="row"
                    sx={{
                        alignItems: "flex-start",
                        gap: "8px",
                        px: "4px",
                        color: "critical.main",
                    }}
                >
                    <HugeiconsIcon
                        icon={AlertCircleIcon}
                        size={18}
                        style={{ flexShrink: 0, marginTop: 1 }}
                    />
                    <Typography
                        sx={{
                            fontSize: 13,
                            lineHeight: "19px",
                            fontWeight: 400,
                        }}
                    >
                        {t("fix_creation_time_completed_with_errors")}
                    </Typography>
                </Stack>
            )}
            <FocusVisibleButton
                type="submit"
                fullWidth
                disabled={
                    !files.length ||
                    (values.option == "custom" && !values.customDate)
                }
                sx={submitButtonSx}
            >
                {t("fix_creation_time")}
            </FocusVisibleButton>
            <Link
                href="https://ente.com/help/photos/faq/metadata-and-editing#fix-time-options"
                target="_blank"
                rel="noopener"
                sx={{
                    fontSize: 12,
                    lineHeight: "16px",
                    color: "text.muted",
                    textAlign: "center",
                }}
            >
                {t("fix_creation_time_options_help")}
            </Link>
        </Stack>
    );
};

const submitButtonSx = {
    ...v2SubmitButtonSx,
    flex: "none",
    minHeight: 52,
    "&.Mui-disabled": {
        color: "text.faint",
        backgroundColor: "fill.faint",
        opacity: 1,
    },
};

const updateFiles = async (
    files: EnteFile[],
    fixOption: FixOption,
    customDate: ParsedMetadataDate | undefined,
    setProgress: (progress: FixProgress) => void,
) => {
    setProgress({ completed: 0, total: files.length });
    let hadErrors = false;
    for (const [i, file] of files.entries()) {
        try {
            await updateFileDate(file, fixOption, customDate);
        } catch (e) {
            log.error(`Failed to update date of ${fileLogID(file)}`, e);
            hadErrors = true;
        } finally {
            setProgress({ completed: i + 1, total: files.length });
        }
    }
    return hadErrors;
};

const updateFileDate = async (
    file: EnteFile,
    fixOption: FixOption,
    customDate: ParsedMetadataDate | undefined,
) => {
    let newDate: ParsedMetadataDate | undefined;

    if (fixOption == "custom") {
        newDate = customDate && {
            dateTime: customDate.dateTime,
            // The picker reports this computer's offset, not the photo's, so
            // leave the offset unset.
            offset: undefined,
            timestamp: customDate.timestamp,
        };
    } else if (fixOption == "file-name") {
        const editedTime = tryParseEpochMicrosecondsFromFileName(
            fileFileName(file),
        );
        if (editedTime === undefined) return;

        const existingDate = fileCreationPhotoDate(file);
        if (editedTime == existingDate.getTime()) return;

        await updateFilePublicMagicMetadata(file, {
            editedTime,
            dateTime: undefined,
            offsetTime: undefined,
        });
        return;
    } else if (file.metadata.fileType == FileType.image) {
        const blob = await downloadManager.fileBlob(file);
        const { DateTimeOriginal, DateTimeDigitized, MetadataDate, DateTime } =
            await extractExifDates(new File([blob], fileFileName(file)));

        switch (fixOption) {
            case "date-time-original":
                newDate = DateTimeOriginal ?? DateTime;
                break;
            case "date-time-digitized":
                newDate = DateTimeDigitized;
                break;
            case "metadata-date":
                newDate = MetadataDate;
                break;
        }
    }

    if (!newDate) return;

    const existingDate = fileCreationPhotoDate(file);
    if (newDate.timestamp == existingDate.getTime()) return;

    await updateFilePublicMagicMetadata(file, {
        dateTime: newDate.dateTime,
        offsetTime: newDate.offset,
        editedTime: newDate.timestamp,
    });
};
