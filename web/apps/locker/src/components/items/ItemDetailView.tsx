import { lockerItemIcon } from "@/components/items/locker-item-icons";
import { downloadLockerFile } from "@/services/download";
import type {
    AccountCredentialData,
    EmergencyContactData,
    GenericFileData,
    LockerItem,
    PersonalNoteData,
    PhysicalRecordData,
} from "@/types";
import { getItemTitle } from "@/types";
import {
    Copy01Icon,
    Delete02Icon,
    Download01Icon,
    Link01Icon,
    PencilEdit02Icon,
    ViewIcon,
    ViewOffSlashIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ArrowBackOutlinedIcon from "@mui/icons-material/ArrowBackOutlined";
import {
    Box,
    Button,
    CircularProgress,
    Drawer,
    IconButton,
    Snackbar,
    Stack,
    Tooltip,
    Typography,
    type Theme,
} from "@mui/material";
import { formattedDateTime } from "ente-base/i18n-date";
import log from "ente-base/log";
import { t } from "i18next";
import React, { useCallback, useState } from "react";
import { typeDisplayName } from "../create-item/item-form-fields-utils";

const textStyles = {
    display2: {
        fontFamily: '"Outfit Variable", sans-serif',
        fontSize: "24px",
        lineHeight: "32px",
        fontWeight: 600,
    },
    bodyBold: { fontSize: "14px", lineHeight: "20px", fontWeight: 600 },
    body: { fontSize: "14px", lineHeight: "20px", fontWeight: 500 },
    mini: { fontSize: "12px", lineHeight: "16px", fontWeight: 500 },
};

interface ItemDetailViewProps {
    item: LockerItem | null;
    collectionNames?: string[];
    onClose: () => void;
    onEdit?: (item: LockerItem) => void;
    onDelete?: (item: LockerItem) => void;
    onDeleteDisabledHint?: string;
    isTrashView?: boolean;
    onShareLink?: (item: LockerItem) => void;
}

export const ItemDetailView: React.FC<ItemDetailViewProps> = ({
    item,
    collectionNames,
    onClose,
    onEdit,
    onDelete,
    onDeleteDisabledHint,
    isTrashView,
    onShareLink,
}) => {
    const [copiedField, setCopiedField] = useState<string | null>(null);
    const [copyError, setCopyError] = useState(false);
    const [downloadError, setDownloadError] = useState(false);
    const [downloading, setDownloading] = useState(false);
    const [downloadProgress, setDownloadProgress] = useState<number | null>(
        null,
    );

    const copyToClipboard = useCallback((value: string, fieldName: string) => {
        void navigator.clipboard
            .writeText(value)
            .then(() => {
                setCopiedField(fieldName);
                setCopyError(false);
                setDownloadError(false);
            })
            .catch((error: unknown) => {
                log.error("Failed to copy Locker item field", error);
                setCopiedField(null);
                setCopyError(true);
            });
    }, []);

    const handleDownload = useCallback(async () => {
        if (!item || downloading) {
            return;
        }

        setDownloading(true);
        setDownloadProgress(null);
        try {
            await downloadLockerFile(
                item.id,
                getItemTitle(item),
                ({ loaded, total }) => {
                    if (total && total > 0) {
                        setDownloadProgress(
                            Math.min(100, Math.round((loaded / total) * 100)),
                        );
                    }
                },
            );
        } catch (error) {
            log.error(`Failed to download file ${item.id}`, error);
            setDownloadError(true);
        } finally {
            setDownloading(false);
            setDownloadProgress(null);
        }
    }, [downloading, item]);

    const actionCount = isTrashView
        ? 0
        : Number(!!onEdit) + Number(!!(onDelete || onDeleteDisabledHint));

    return (
        <Drawer
            anchor="right"
            open={item !== null}
            onClose={onClose}
            slotProps={{
                paper: {
                    sx: [
                        {
                            width: { xs: "100%", sm: 420 },
                            backgroundColor: "#f4f4f4",
                            "&&": { p: 0 },
                        },
                        (theme) =>
                            theme.applyStyles("dark", {
                                backgroundColor: "#161616",
                            }),
                    ],
                },
            }}
        >
            {item && (
                <Stack sx={{ height: "100%" }}>
                    <Box
                        sx={{
                            position: "relative",
                            flexShrink: 0,
                            height: 112,
                            px: 2,
                            pt: "48px",
                        }}
                    >
                        <IconButton
                            onClick={onClose}
                            aria-label={t("close")}
                            sx={{
                                position: "absolute",
                                left: 6,
                                top: 6,
                                "&&": { p: "10px" },
                            }}
                        >
                            <ArrowBackOutlinedIcon sx={{ fontSize: 24 }} />
                        </IconButton>
                        <Box
                            sx={{
                                minWidth: 0,
                                pr: actionCount
                                    ? `${actionCount * 40 + 8}px`
                                    : 0,
                            }}
                        >
                            <Typography
                                variant="h3"
                                noWrap
                                sx={{ ...textStyles.display2 }}
                            >
                                {getItemTitle(item)}
                            </Typography>
                            <Typography
                                variant="mini"
                                sx={{
                                    ...textStyles.mini,
                                    color: "text.muted",
                                    mt: "4px",
                                }}
                            >
                                {typeDisplayName(item.type)}
                            </Typography>
                        </Box>
                        <Stack
                            direction="row"
                            sx={{
                                position: "absolute",
                                right: 16,
                                top: 45,
                                gap: 1,
                            }}
                        >
                            {!isTrashView && onEdit && (
                                <Tooltip title={t("edit")}>
                                    <IconButton
                                        onClick={() => onEdit(item)}
                                        size="small"
                                        aria-label={t("edit")}
                                        sx={actionButtonSx}
                                    >
                                        <HugeiconsIcon
                                            icon={PencilEdit02Icon}
                                            size={18}
                                            strokeWidth={1.5}
                                            color="currentColor"
                                        />
                                    </IconButton>
                                </Tooltip>
                            )}
                            {!isTrashView &&
                                (onDelete || onDeleteDisabledHint) && (
                                    <Tooltip
                                        title={
                                            onDelete
                                                ? t("delete")
                                                : (onDeleteDisabledHint ?? "")
                                        }
                                    >
                                        <Box component="span">
                                            <IconButton
                                                onClick={
                                                    onDelete
                                                        ? () => onDelete(item)
                                                        : undefined
                                                }
                                                size="small"
                                                disabled={!onDelete}
                                                aria-label={t("delete")}
                                                sx={[
                                                    actionButtonSx,
                                                    onDelete
                                                        ? {
                                                              color: "critical.main",
                                                          }
                                                        : {},
                                                ]}
                                            >
                                                <HugeiconsIcon
                                                    icon={Delete02Icon}
                                                    size={18}
                                                    strokeWidth={1.5}
                                                    color="currentColor"
                                                />
                                            </IconButton>
                                        </Box>
                                    </Tooltip>
                                )}
                        </Stack>
                    </Box>

                    <Stack
                        sx={{
                            flex: 1,
                            overflowY: "auto",
                            minHeight: 0,
                            px: 2,
                            pb: 2,
                            "& > *": { flexShrink: 0 },
                        }}
                    >
                        {item.type === "note" && (
                            <NoteDetail
                                data={item.data as PersonalNoteData}
                                onCopy={copyToClipboard}
                            />
                        )}
                        {item.type === "accountCredential" && (
                            <CredentialDetail
                                data={item.data as AccountCredentialData}
                                onCopy={copyToClipboard}
                            />
                        )}
                        {item.type === "physicalRecord" && (
                            <PhysicalRecordDetail
                                data={item.data as PhysicalRecordData}
                                onCopy={copyToClipboard}
                            />
                        )}
                        {item.type === "emergencyContact" && (
                            <EmergencyContactDetail
                                data={item.data as EmergencyContactData}
                                onCopy={copyToClipboard}
                            />
                        )}
                        {item.type === "file" && (
                            <FileDetail
                                data={item.data as GenericFileData}
                                onCopy={copyToClipboard}
                            />
                        )}
                        {!!collectionNames?.length && (
                            <Stack sx={{ gap: 1, mb: 3 }}>
                                <Typography
                                    variant="body"
                                    sx={{ ...textStyles.bodyBold, mt: "8px" }}
                                >
                                    {t("collections")}
                                </Typography>
                                <Stack
                                    direction="row"
                                    sx={{ flexWrap: "wrap", gap: "12px 8px" }}
                                >
                                    {collectionNames.map((name, index) => (
                                        <Typography
                                            key={`${name}-${index}`}
                                            variant="body"
                                            sx={(theme) => ({
                                                ...textStyles.body,
                                                minHeight: 44,
                                                px: 2.5,
                                                py: 1.5,
                                                borderRadius: "16px",
                                                backgroundColor:
                                                    theme.vars.palette
                                                        .background.paper,
                                                color: "text.muted",
                                                overflowWrap: "anywhere",
                                            })}
                                        >
                                            {name}
                                        </Typography>
                                    ))}
                                </Stack>
                            </Stack>
                        )}
                        <Box sx={{ flex: 1 }} />
                        {item.type === "file" && (
                            <Button
                                variant="contained"
                                color="accent"
                                sx={{
                                    ...textStyles.bodyBold,
                                    minHeight: 52,
                                    borderRadius: "20px",
                                    mb: 1,
                                }}
                                endIcon={
                                    downloading && downloadProgress !== null ? (
                                        <CircularProgress
                                            variant="determinate"
                                            value={downloadProgress}
                                            size={16}
                                            thickness={6}
                                            color="inherit"
                                        />
                                    ) : undefined
                                }
                                startIcon={
                                    <HugeiconsIcon
                                        icon={Download01Icon}
                                        size={18}
                                        strokeWidth={1.5}
                                        color="currentColor"
                                    />
                                }
                                onClick={() => void handleDownload()}
                                disabled={downloading}
                                fullWidth
                            >
                                {downloading
                                    ? downloadProgress !== null
                                        ? `${t("downloading")} ${downloadProgress}%`
                                        : t("downloading")
                                    : t("download")}
                            </Button>
                        )}
                        {onShareLink && (
                            <Button
                                variant="contained"
                                color="secondary"
                                sx={[
                                    (theme) => ({
                                        ...textStyles.bodyBold,
                                        minHeight: 52,
                                        borderRadius: "20px",
                                        backgroundColor:
                                            theme.vars.palette.fill.faint,
                                        color: theme.vars.palette.text.base,
                                        "&:hover": {
                                            backgroundColor: "#dedede",
                                        },
                                    }),
                                    (theme) =>
                                        theme.applyStyles("dark", {
                                            "&:hover": {
                                                backgroundColor: "#141414",
                                            },
                                        }),
                                ]}
                                startIcon={
                                    <HugeiconsIcon
                                        icon={Link01Icon}
                                        size={18}
                                        strokeWidth={1.5}
                                        color="currentColor"
                                    />
                                }
                                onClick={() => onShareLink(item)}
                                fullWidth
                            >
                                {t("shareLink")}
                            </Button>
                        )}
                        {item.updatedAt && (
                            <Typography
                                variant="mini"
                                sx={{
                                    color: "text.muted",
                                    ...textStyles.mini,
                                    textAlign: "center",
                                    mt: 2,
                                }}
                            >
                                {t("lastUpdated")}:{" "}
                                {formattedDateTime(item.updatedAt)}
                            </Typography>
                        )}
                    </Stack>
                </Stack>
            )}

            <Snackbar
                open={copyError || downloadError || copiedField !== null}
                message={
                    copyError
                        ? t("copyFailed")
                        : downloadError
                          ? t("downloadFailed")
                          : t("copiedToClipboard", { fieldName: copiedField })
                }
                autoHideDuration={2000}
                onClose={() => {
                    setCopiedField(null);
                    setCopyError(false);
                    setDownloadError(false);
                }}
            />
        </Drawer>
    );
};

interface FieldRowProps {
    label: string;
    value: string;
    onCopy: (value: string, field: string) => void;
    secret?: boolean;
    multiline?: boolean;
}

const FieldRow: React.FC<FieldRowProps> = ({
    label,
    value,
    onCopy,
    secret,
    multiline,
}) => {
    const [revealed, setRevealed] = useState(false);

    if (!value) {
        return null;
    }

    const displayValue =
        secret && !revealed
            ? "\u2022".repeat(Math.min(value.length, 16))
            : value;

    return (
        <Stack sx={{ gap: 1, mb: 3 }}>
            <Typography variant="body" sx={{ ...textStyles.body }}>
                {label}
            </Typography>
            <Stack
                direction="row"
                sx={(theme) => ({
                    alignItems: multiline ? "flex-start" : "center",
                    minHeight: 52,
                    borderRadius: "16px",
                    backgroundColor: theme.vars.palette.background.paper,
                    border: `1px solid ${theme.vars.palette.divider}`,
                    px: 2,
                    py: multiline ? 2 : 0,
                    gap: 0.5,
                })}
            >
                <Typography
                    variant="body"
                    sx={{
                        ...textStyles.body,
                        flex: 1,
                        minWidth: 0,
                        letterSpacing:
                            secret && !revealed ? "0.14em" : undefined,
                        whiteSpace: multiline ? "pre-wrap" : "nowrap",
                        overflow: multiline ? "visible" : "hidden",
                        textOverflow: multiline ? "unset" : "ellipsis",
                        wordBreak: multiline ? "break-word" : undefined,
                    }}
                >
                    {displayValue}
                </Typography>
                <Stack direction="row" sx={{ gap: 0, mr: "-4px" }}>
                    {secret && (
                        <Tooltip
                            title={
                                revealed ? t("hidePassword") : t("showPassword")
                            }
                        >
                            <IconButton
                                size="small"
                                aria-label={
                                    revealed
                                        ? t("hidePassword")
                                        : t("showPassword")
                                }
                                sx={{
                                    color: "inherit",
                                    flexShrink: 0,
                                    "&&": { p: "4px", borderRadius: "8px" },
                                }}
                                onClick={() => setRevealed((value) => !value)}
                            >
                                {revealed ? (
                                    <HugeiconsIcon
                                        icon={ViewOffSlashIcon}
                                        size={18}
                                        strokeWidth={1.5}
                                        color="currentColor"
                                    />
                                ) : (
                                    <HugeiconsIcon
                                        icon={ViewIcon}
                                        size={18}
                                        strokeWidth={1.5}
                                        color="currentColor"
                                    />
                                )}
                            </IconButton>
                        </Tooltip>
                    )}
                    <Tooltip title={t("copy")}>
                        <IconButton
                            size="small"
                            aria-label={t("copy")}
                            sx={{
                                color: "inherit",
                                flexShrink: 0,
                                "&&": { p: "4px", borderRadius: "8px" },
                            }}
                            onClick={() => onCopy(value, label)}
                        >
                            <HugeiconsIcon
                                icon={Copy01Icon}
                                size={18}
                                strokeWidth={1.5}
                                color="currentColor"
                            />
                        </IconButton>
                    </Tooltip>
                </Stack>
            </Stack>
        </Stack>
    );
};

const NoteDetail: React.FC<{
    data: PersonalNoteData;
    onCopy: (value: string, field: string) => void;
}> = ({ data, onCopy }) => (
    <FieldRow
        label={t("noteContent")}
        value={data.content}
        onCopy={onCopy}
        multiline
    />
);

const CredentialDetail: React.FC<{
    data: AccountCredentialData;
    onCopy: (value: string, field: string) => void;
}> = ({ data, onCopy }) => (
    <>
        <FieldRow label={t("username")} value={data.username} onCopy={onCopy} />
        <FieldRow
            label={t("password")}
            value={data.password}
            onCopy={onCopy}
            secret
        />
        {data.notes && (
            <FieldRow
                label={t("credentialNotes")}
                value={data.notes}
                onCopy={onCopy}
                multiline
            />
        )}
    </>
);

const PhysicalRecordDetail: React.FC<{
    data: PhysicalRecordData;
    onCopy: (value: string, field: string) => void;
}> = ({ data, onCopy }) => (
    <>
        <FieldRow
            label={t("recordLocation")}
            value={data.location}
            onCopy={onCopy}
        />
        {data.notes && (
            <FieldRow
                label={t("recordNotes")}
                value={data.notes}
                onCopy={onCopy}
                multiline
            />
        )}
    </>
);

const EmergencyContactDetail: React.FC<{
    data: EmergencyContactData;
    onCopy: (value: string, field: string) => void;
}> = ({ data, onCopy }) => (
    <>
        <FieldRow
            label={t("contactDetails")}
            value={data.contactDetails}
            onCopy={onCopy}
        />
        {data.notes && (
            <FieldRow
                label={t("contactNotes")}
                value={data.notes}
                onCopy={onCopy}
                multiline
            />
        )}
    </>
);

const actionButtonSx = (theme: Theme) => ({
    "&&": { width: 36, height: 36, p: 0, borderRadius: "12px" },
    "&:hover": { backgroundColor: theme.vars.palette.fill.faint },
});

const formattedBytes = (bytes: number) => {
    const units = ["B", "KB", "MB", "GB", "TB"];
    const index = Math.min(
        Math.floor(Math.log(Math.max(bytes, 1)) / Math.log(1024)),
        units.length - 1,
    );
    return `${Number((bytes / 1024 ** index).toFixed(1))} ${units[index]}`;
};

const FileDetail: React.FC<{
    data: GenericFileData;
    onCopy: (value: string, field: string) => void;
}> = ({ data, onCopy }) => {
    const suffix = /\.([a-z0-9]{1,5})$/i.exec(data.name)?.[1];
    const extension =
        suffix && /[a-z]/i.test(suffix) ? suffix.toUpperCase() : undefined;
    const meta = [
        extension,
        data.fileSize === undefined ? undefined : formattedBytes(data.fileSize),
    ]
        .filter(Boolean)
        .join(" · ");
    return (
        <>
            <Stack
                sx={(theme) => ({
                    height: 180,
                    borderRadius: "20px",
                    backgroundColor: theme.vars.palette.background.paper,
                    alignItems: "center",
                    justifyContent: "center",
                    gap: "10px",
                    mb: 3,
                })}
            >
                <Box
                    sx={[
                        {
                            width: 56,
                            height: 56,
                            borderRadius: "16px",
                            backgroundColor: "#f4f4f4",
                            display: "grid",
                            placeItems: "center",
                        },
                        (theme) =>
                            theme.applyStyles("dark", {
                                backgroundColor: "#161616",
                            }),
                    ]}
                >
                    {lockerItemIcon("file", {
                        fileName: data.name,
                        size: 32,
                        strokeWidth: 1.5,
                    })}
                </Box>
                {meta && (
                    <Typography
                        variant="mini"
                        sx={{ ...textStyles.mini, color: "text.muted" }}
                    >
                        {meta}
                    </Typography>
                )}
            </Stack>
            <FieldRow
                label={t("fileTitle")}
                value={data.name}
                onCopy={onCopy}
            />
        </>
    );
};
