import { lockerSheetContainerSx, lockerSheetPaperSx } from "@/styles/dialog";
import {
    lockerColorSx,
    lockerShadowFloating,
    lockerTextBodyBoldSx,
    lockerTextBodySx,
    lockerTextH2Sx,
} from "@/styles/tokens";
import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ContentCopyIcon from "@mui/icons-material/ContentCopy";
import {
    Box,
    Button,
    CircularProgress,
    Dialog,
    IconButton,
    Stack,
    Typography,
} from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { t } from "i18next";
import React, { useId } from "react";

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
}) => {
    const titleID = useId();
    return (
        <Dialog
            open={open}
            aria-labelledby={titleID}
            onClose={loading || deleting ? undefined : onClose}
            fullWidth={!loading}
            maxWidth={loading ? false : "xs"}
            slotProps={{
                paper: {
                    sx: loading
                        ? (theme) => ({
                              display: "flex",
                              flexDirection: "row",
                              alignItems: "center",
                              gap: 2,
                              padding: "20px 24px",
                              borderRadius: "20px",
                              ...lockerColorSx(theme, {
                                  backgroundColor: "backgroundBase",
                              }),
                              boxShadow: lockerShadowFloating,
                              width: "auto",
                          })
                        : lockerSheetPaperSx,
                },
                container: {
                    sx: loading
                        ? { alignItems: "center" }
                        : lockerSheetContainerSx,
                },
            }}
        >
            {loading ? (
                <>
                    <CircularProgress
                        size={24}
                        thickness={4}
                        sx={(theme) =>
                            lockerColorSx(theme, { color: "primary" })
                        }
                    />
                    <Typography id={titleID} sx={lockerTextBodySx}>
                        {t("creatingShareLink")}
                    </Typography>
                </>
            ) : (
                <Stack>
                    <Stack
                        direction="row"
                        sx={{ alignItems: "center", gap: 1.5, minHeight: 38 }}
                    >
                        <Typography
                            id={titleID}
                            noWrap
                            sx={{ ...lockerTextH2Sx, flex: 1, minWidth: 0 }}
                        >
                            {itemTitle}
                        </Typography>
                        <IconButton
                            aria-label={t("cancel")}
                            onClick={onClose}
                            disabled={deleting}
                            sx={(theme) => ({
                                width: 36,
                                height: 36,
                                borderRadius: "50%",
                                p: 0,
                                flexShrink: 0,
                                ...lockerColorSx(theme, {
                                    backgroundColor: "fillLight",
                                    color: "iconColor",
                                }),
                                "&:hover": {
                                    ...lockerColorSx(theme, {
                                        backgroundColor: "fillHover",
                                    }),
                                },
                            })}
                        >
                            <HugeiconsIcon
                                icon={Cancel01Icon}
                                size={18}
                                strokeWidth={1.5}
                            />
                        </IconButton>
                    </Stack>
                    <Typography
                        sx={(theme) => ({
                            ...lockerTextBodySx,
                            mt: 2,
                            ...lockerColorSx(theme, { color: "textLight" }),
                        })}
                    >
                        {t("shareThisLink")}
                    </Typography>
                    <Box
                        sx={(theme) => ({
                            position: "relative",
                            mt: 3,
                            borderRadius: "12px",
                            padding: "16px 48px 16px 12px",
                            ...lockerColorSx(theme, {
                                backgroundColor: "fillLight",
                            }),
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
                        <IconButton
                            aria-label={t("copyLink")}
                            onClick={onCopy}
                            disabled={!url || deleting}
                            sx={(theme) => ({
                                position: "absolute",
                                right: 6,
                                top: 6,
                                width: 36,
                                height: 36,
                                borderRadius: "50%",
                                ...lockerColorSx(theme, { color: "iconColor" }),
                                "&:hover": {
                                    ...lockerColorSx(theme, {
                                        backgroundColor: "fillHover",
                                    }),
                                },
                            })}
                        >
                            <ContentCopyIcon sx={{ fontSize: 18 }} />
                        </IconButton>
                    </Box>
                    <Stack sx={{ gap: 1.5, mt: 2 }}>
                        <Button
                            fullWidth
                            onClick={showShareAction ? onShare : onCopy}
                            disabled={!url || deleting}
                            sx={(theme) => ({
                                ...lockerTextBodyBoldSx,
                                minHeight: 52,
                                borderRadius: "20px",
                                textTransform: "none",
                                ...lockerColorSx(theme, {
                                    backgroundColor: "primary",
                                    color: "specialWhite",
                                }),
                                "&:hover": {
                                    ...lockerColorSx(theme, {
                                        backgroundColor: "primaryDark",
                                    }),
                                },
                            })}
                        >
                            {showShareAction ? t("shareLink") : t("copyLink")}
                        </Button>
                        <LoadingButton
                            fullWidth
                            variant="text"
                            color="critical"
                            loading={deleting}
                            onClick={onDelete}
                            sx={(theme) => ({
                                ...lockerTextBodyBoldSx,
                                minHeight: 52,
                                borderRadius: "20px",
                                textTransform: "none",
                                backgroundColor: "transparent",
                                ...lockerColorSx(theme, { color: "warning" }),
                                "&.Mui-disabled": {
                                    backgroundColor: "transparent",
                                    ...lockerColorSx(theme, {
                                        color: "warning",
                                    }),
                                },
                                "&:hover": {
                                    ...lockerColorSx(theme, {
                                        backgroundColor: "warningLight",
                                    }),
                                },
                            })}
                        >
                            {deleting
                                ? t("deletingShareLink")
                                : t("deleteLink")}
                        </LoadingButton>
                    </Stack>
                </Stack>
            )}
        </Dialog>
    );
};
