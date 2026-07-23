import { downloadLockerFile } from "@/services/remote";
import type {
    AccountCredentialData,
    EmergencyContactData,
    GenericFileData,
    LockerItem,
    PersonalNoteData,
    PhysicalRecordData,
} from "@/types";
import { getItemTitle } from "@/types";
import CloseIcon from "@mui/icons-material/Close";
import ContentCopyIcon from "@mui/icons-material/ContentCopy";
import DeleteOutlinedIcon from "@mui/icons-material/DeleteOutlined";
import EditOutlinedIcon from "@mui/icons-material/EditOutlined";
import FileDownloadOutlinedIcon from "@mui/icons-material/FileDownloadOutlined";
import ShareOutlinedIcon from "@mui/icons-material/ShareOutlined";
import VisibilityIcon from "@mui/icons-material/Visibility";
import VisibilityOffIcon from "@mui/icons-material/VisibilityOff";
import {
    Box,
    Button,
    CircularProgress,
    Divider,
    Drawer,
    IconButton,
    Snackbar,
    Stack,
    Tooltip,
    Typography,
} from "@mui/material";
import { formattedDateTime } from "ente-base/i18n-date";
import log from "ente-base/log";
import { t } from "i18next";
import React, { useCallback, useState } from "react";

interface ItemDetailViewProps {
    item: LockerItem | null;
    masterKey?: string;
    onClose: () => void;
    onEdit?: (item: LockerItem) => void;
    onDelete?: (item: LockerItem) => void;
    onDeleteDisabledHint?: string;
    isTrashView?: boolean;
    onShareLink?: (item: LockerItem) => void;
}

export const ItemDetailView: React.FC<ItemDetailViewProps> = ({
    item,
    masterKey,
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
        if (!item || !masterKey || downloading) {
            return;
        }

        setDownloading(true);
        setDownloadProgress(null);
        try {
            await downloadLockerFile(
                item.id,
                getItemTitle(item),
                masterKey,
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
    }, [downloading, item, masterKey]);

    return (
        <Drawer
            anchor="right"
            open={item !== null}
            onClose={onClose}
            sx={{ "& .MuiDrawer-paper": { width: "min(420px, 90vw)", p: 0 } }}
        >
            {item && (
                <Stack sx={{ height: "100%" }}>
                    <Stack
                        direction="row"
                        sx={{
                            alignItems: "center",
                            gap: 1,
                            px: 2.5,
                            py: 2,
                            borderBottom: 1,
                            borderColor: "divider",
                        }}
                    >
                        <Box sx={{ flex: 1, minWidth: 0 }}>
                            <Typography
                                variant="h3"
                                noWrap
                                sx={{ lineHeight: 1.3 }}
                            >
                                {getItemTitle(item)}
                            </Typography>
                            <Typography
                                variant="small"
                                sx={{ color: "text.faint" }}
                            >
                                {typeLabel(item.type)}
                            </Typography>
                        </Box>
                        {!isTrashView && onEdit && (
                            <Tooltip title={t("edit")}>
                                <IconButton
                                    onClick={() => onEdit(item)}
                                    size="small"
                                >
                                    <EditOutlinedIcon fontSize="small" />
                                </IconButton>
                            </Tooltip>
                        )}
                        {!isTrashView && (onDelete || onDeleteDisabledHint) && (
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
                                        sx={
                                            onDelete
                                                ? { color: "critical.main" }
                                                : undefined
                                        }
                                    >
                                        <DeleteOutlinedIcon fontSize="small" />
                                    </IconButton>
                                </Box>
                            </Tooltip>
                        )}
                        <IconButton onClick={onClose} size="small">
                            <CloseIcon />
                        </IconButton>
                    </Stack>

                    <Stack
                        sx={{
                            flex: 1,
                            overflowY: "auto",
                            px: 2.5,
                            py: 2,
                            gap: 2.5,
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
                            <>
                                <FileDetail
                                    data={item.data as GenericFileData}
                                    onCopy={copyToClipboard}
                                />
                                {masterKey && (
                                    <Stack sx={{ mt: 1, gap: 1 }}>
                                        <Button
                                            variant="contained"
                                            endIcon={
                                                downloading &&
                                                downloadProgress !== null ? (
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
                                                <FileDownloadOutlinedIcon />
                                            }
                                            onClick={() =>
                                                void handleDownload()
                                            }
                                            disabled={downloading}
                                            fullWidth
                                        >
                                            {downloading
                                                ? downloadProgress !== null
                                                    ? `${t("downloading")} ${downloadProgress}%`
                                                    : t("downloading")
                                                : t("download")}
                                        </Button>
                                    </Stack>
                                )}
                            </>
                        )}
                        {onShareLink && (
                            <Button
                                variant="outlined"
                                startIcon={<ShareOutlinedIcon />}
                                onClick={() => onShareLink(item)}
                                fullWidth
                            >
                                {t("shareLink")}
                            </Button>
                        )}
                    </Stack>

                    {item.updatedAt && (
                        <Box
                            sx={{
                                px: 2.5,
                                py: 1.5,
                                borderTop: 1,
                                borderColor: "divider",
                            }}
                        >
                            <Typography
                                variant="mini"
                                sx={{ color: "text.faint" }}
                            >
                                {t("lastUpdated")}:{" "}
                                {formattedDateTime(item.updatedAt)}
                            </Typography>
                        </Box>
                    )}
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

const typeLabel = (type: string): string => {
    switch (type) {
        case "note":
            return t("personalNote");
        case "accountCredential":
            return t("secret");
        case "physicalRecord":
            return t("thing");
        case "emergencyContact":
            return t("emergencyContact");
        case "file":
            return t("document");
        default:
            return type;
    }
};

interface FieldRowProps {
    label: string;
    value: string;
    onCopy: (value: string, field: string) => void;
    monospace?: boolean;
    secret?: boolean;
    multiline?: boolean;
}

const FieldRow: React.FC<FieldRowProps> = ({
    label,
    value,
    onCopy,
    monospace,
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
        <Stack sx={{ gap: 0.5 }}>
            <Typography
                variant="mini"
                sx={{
                    color: "text.faint",
                    textTransform: "uppercase",
                    letterSpacing: "0.08em",
                    fontWeight: "bold",
                }}
            >
                {label}
            </Typography>
            <Stack direction="row" sx={{ alignItems: "flex-start", gap: 0.5 }}>
                <Typography
                    variant="body"
                    sx={{
                        flex: 1,
                        fontFamily: monospace ? "monospace" : undefined,
                        whiteSpace: multiline ? "pre-wrap" : "nowrap",
                        overflow: multiline ? "visible" : "hidden",
                        textOverflow: multiline ? "unset" : "ellipsis",
                        wordBreak: multiline ? "break-word" : undefined,
                    }}
                >
                    {displayValue}
                </Typography>
                {secret && (
                    <Tooltip
                        title={revealed ? t("hidePassword") : t("showPassword")}
                    >
                        <IconButton
                            size="small"
                            onClick={() => setRevealed((value) => !value)}
                        >
                            {revealed ? (
                                <VisibilityOffIcon fontSize="small" />
                            ) : (
                                <VisibilityIcon fontSize="small" />
                            )}
                        </IconButton>
                    </Tooltip>
                )}
                <Tooltip title={t("copy")}>
                    <IconButton
                        size="small"
                        onClick={() => onCopy(value, label)}
                    >
                        <ContentCopyIcon fontSize="small" />
                    </IconButton>
                </Tooltip>
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
        <Divider />
        <FieldRow
            label={t("password")}
            value={data.password}
            onCopy={onCopy}
            secret
            monospace
        />
        {data.notes && (
            <>
                <Divider />
                <FieldRow
                    label={t("credentialNotes")}
                    value={data.notes}
                    onCopy={onCopy}
                    multiline
                />
            </>
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
            <>
                <Divider />
                <FieldRow
                    label={t("recordNotes")}
                    value={data.notes}
                    onCopy={onCopy}
                    multiline
                />
            </>
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
            <>
                <Divider />
                <FieldRow
                    label={t("contactNotes")}
                    value={data.notes}
                    onCopy={onCopy}
                    multiline
                />
            </>
        )}
    </>
);

const FileDetail: React.FC<{
    data: GenericFileData;
    onCopy: (value: string, field: string) => void;
}> = ({ data, onCopy }) => (
    <FieldRow label={t("fileTitle")} value={data.name} onCopy={onCopy} />
);
