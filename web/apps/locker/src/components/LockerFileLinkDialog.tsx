import { lockerDialogPaperSx } from "@/components/lockerDialogStyles";
import CloseIcon from "@mui/icons-material/Close";
import ContentCopyIcon from "@mui/icons-material/ContentCopy";
import {
    Box,
    Button,
    CircularProgress,
    Dialog,
    DialogContent,
    DialogTitle,
    IconButton,
    Stack,
    Typography,
} from "@mui/material";
import { t } from "i18next";
import React from "react";

interface LockerFileLinkDialogProps {
    open: boolean;
    itemTitle: string;
    url?: string;
    loading: boolean;
    deleting: boolean;
    showShareAction?: boolean;
    onClose: () => void;
    onCopy: () => void;
    onShare: () => void;
    onDelete: () => void;
}

export const LockerFileLinkDialog: React.FC<LockerFileLinkDialogProps> = ({
    open,
    itemTitle,
    url,
    loading,
    deleting,
    showShareAction,
    onClose,
    onCopy,
    onShare,
    onDelete,
}) => (
    <Dialog
        open={open}
        onClose={loading || deleting ? undefined : onClose}
        fullWidth
        maxWidth="xs"
        slotProps={{
            paper: {
                sx: { ...lockerDialogPaperSx, width: "min(100%, 420px)" },
            },
        }}
    >
        <DialogTitle sx={{ pr: 6 }}>
            {itemTitle}
            <IconButton
                onClick={onClose}
                size="small"
                sx={{ position: "absolute", right: 12, top: 12 }}
                disabled={loading || deleting}
            >
                <CloseIcon fontSize="small" />
            </IconButton>
        </DialogTitle>
        <DialogContent sx={{ pb: 3 }}>
            {loading ? (
                <Stack
                    sx={{
                        minHeight: 180,
                        alignItems: "center",
                        justifyContent: "center",
                        gap: 1.5,
                    }}
                >
                    <CircularProgress size={28} />
                    <Typography variant="body" sx={{ color: "text.muted" }}>
                        {t("creatingShareLink")}
                    </Typography>
                </Stack>
            ) : (
                <Stack sx={{ gap: 2 }}>
                    <Typography variant="body" sx={{ color: "text.muted" }}>
                        {t("shareThisLink")}
                    </Typography>

                    <Box
                        sx={(theme) => ({
                            p: 1.5,
                            borderRadius: "12px",
                            bgcolor: theme.vars.palette.fill.faint,
                        })}
                    >
                        <Typography
                            component="div"
                            sx={{
                                wordBreak: "break-all",
                                fontSize: 13,
                                lineHeight: 1.5,
                                fontFamily:
                                    'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace',
                            }}
                        >
                            {url}
                        </Typography>
                    </Box>

                    <Stack
                        direction={{ xs: "column", sm: "row" }}
                        sx={{ gap: 1 }}
                    >
                        <Button
                            variant="contained"
                            startIcon={<ContentCopyIcon />}
                            onClick={onCopy}
                            disabled={!url || deleting}
                            fullWidth
                        >
                            {t("copyLink")}
                        </Button>
                        {showShareAction && (
                            <Button
                                variant="outlined"
                                onClick={onShare}
                                disabled={!url || deleting}
                                fullWidth
                            >
                                {t("shareLink")}
                            </Button>
                        )}
                    </Stack>

                    <Button
                        variant="text"
                        color="critical"
                        onClick={onDelete}
                        disabled={deleting}
                    >
                        {deleting ? t("deletingShareLink") : t("deleteLink")}
                    </Button>
                </Stack>
            )}
        </DialogContent>
    </Dialog>
);
