import {
    lockerItemIcon,
    lockerItemIconConfig,
} from "@/components/lockerItemIcons";
import { downloadLockerFile } from "@/services/remote";
import type { GenericFileData, LockerItem } from "@/types";
import { getItemTitle, hasDownloadableObject } from "@/types";
import { CircleArrowDownLeftIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import CheckCircleRoundedIcon from "@mui/icons-material/CheckCircleRounded";
import DeleteOutlinedIcon from "@mui/icons-material/DeleteOutlined";
import EditOutlinedIcon from "@mui/icons-material/EditOutlined";
import MoreVertIcon from "@mui/icons-material/MoreVert";
import RadioButtonUncheckedRoundedIcon from "@mui/icons-material/RadioButtonUncheckedRounded";
import RestoreIcon from "@mui/icons-material/Restore";
import ShareOutlinedIcon from "@mui/icons-material/ShareOutlined";
import {
    Box,
    ButtonBase,
    CircularProgress,
    IconButton,
    Snackbar,
    Stack,
    Tooltip,
    Typography,
} from "@mui/material";
import {
    OverflowMenu,
    OverflowMenuOption,
} from "ente-base/components/OverflowMenu";
import log from "ente-base/log";
import { t } from "i18next";
import React, { useCallback, useState } from "react";

interface ItemCardProps {
    item: LockerItem;
    /** The user's master key, needed for file downloads. */
    masterKey?: string;
    onClick: () => void;
    /** Whether this card is shown in the trash view. */
    isTrashView?: boolean;
    isIncomingShared?: boolean;
    /** Called when the user wants to edit this item. */
    onEdit?: (item: LockerItem) => void;
    /** Called when the user wants to delete (trash) this item. */
    onDelete?: (item: LockerItem) => void;
    /** Optional hint shown when delete is unavailable for this item. */
    deleteDisabledHint?: string;
    /** Called when the user wants to permanently delete this item. */
    onPermanentlyDelete?: (items: LockerItem[]) => void;
    /** Called when the user wants to restore this item from trash. */
    onRestore?: (item: LockerItem) => void;
    onShareLink?: (item: LockerItem) => void;
    selectionMode?: boolean;
    selectable?: boolean;
    selected?: boolean;
    onToggleSelection?: (item: LockerItem) => void;
    onLongPressSelect?: (item: LockerItem) => void;
}

/**
 * A file/item row matching the Figma design:
 * Light rounded card background — colored icon (in rounded square) — title — actions
 */
export const ItemCard: React.FC<ItemCardProps> = React.memo(function ItemCard({
    item,
    masterKey,
    onClick,
    isTrashView,
    isIncomingShared,
    onEdit,
    onDelete,
    deleteDisabledHint,
    onPermanentlyDelete,
    onRestore,
    onShareLink,
    selectionMode,
    selectable,
    selected,
    onToggleSelection,
    onLongPressSelect,
}) {
    const [downloadError, setDownloadError] = useState(false);
    const [downloading, setDownloading] = useState(false);
    const [downloadProgress, setDownloadProgress] = useState<number | null>(
        null,
    );
    const longPressTimerRef = React.useRef<number | null>(null);
    const longPressTriggeredRef = React.useRef(false);

    const handleDownload = useCallback(async () => {
        if (!masterKey || downloading || !hasDownloadableObject(item)) return;
        setDownloading(true);
        setDownloadProgress(null);
        try {
            const fileName = getItemTitle(item);
            await downloadLockerFile(
                item.id,
                fileName,
                masterKey,
                ({ loaded, total }) => {
                    if (total && total > 0) {
                        setDownloadProgress(
                            Math.min(100, Math.round((loaded / total) * 100)),
                        );
                    }
                },
            );
        } catch (e) {
            log.error(`Failed to download file ${item.id}`, e);
            setDownloadError(true);
        } finally {
            setDownloading(false);
            setDownloadProgress(null);
        }
    }, [item, masterKey, downloading]);

    const title = getItemTitle(item);
    const downloadable = hasDownloadableObject(item);
    const clearLongPress = useCallback(() => {
        if (longPressTimerRef.current !== null) {
            window.clearTimeout(longPressTimerRef.current);
            longPressTimerRef.current = null;
        }
    }, []);
    const handlePressStart = useCallback(
        (event: React.PointerEvent<HTMLDivElement>) => {
            if (
                selectionMode ||
                !selectable ||
                !onLongPressSelect ||
                (event.button !== -1 && event.button !== 0)
            ) {
                return;
            }

            const target = event.target;
            if (
                target instanceof Element &&
                target.closest("[data-no-long-press='true']")
            ) {
                return;
            }

            clearLongPress();
            longPressTriggeredRef.current = false;
            longPressTimerRef.current = window.setTimeout(() => {
                longPressTriggeredRef.current = true;
                onLongPressSelect(item);
            }, 420);
        },
        [clearLongPress, item, onLongPressSelect, selectable, selectionMode],
    );
    const handlePressEnd = useCallback(() => {
        clearLongPress();
    }, [clearLongPress]);

    React.useEffect(
        () => () => {
            clearLongPress();
        },
        [clearLongPress],
    );

    return (
        <>
            <ButtonBase
                component="div"
                onPointerDown={handlePressStart}
                onPointerUp={handlePressEnd}
                onPointerLeave={handlePressEnd}
                onPointerCancel={handlePressEnd}
                onContextMenu={(event) => {
                    if (!selectionMode && selectable && onLongPressSelect) {
                        event.preventDefault();
                    }
                }}
                onClick={() => {
                    if (longPressTriggeredRef.current) {
                        longPressTriggeredRef.current = false;
                        return;
                    }
                    if (selectionMode) {
                        if (selectable && onToggleSelection) {
                            onToggleSelection(item);
                        }
                        return;
                    }
                    if (
                        !isTrashView &&
                        item.type === "file" &&
                        masterKey &&
                        downloadable
                    ) {
                        void handleDownload();
                        return;
                    }
                    onClick();
                }}
                sx={(theme) => ({
                    display: "flex",
                    width: "100%",
                    textAlign: "left",
                    borderRadius: "18px",
                    overflow: "hidden",
                    px: 1.5,
                    py: 1.25,
                    gap: 1.25,
                    alignItems: "center",
                    backgroundColor: theme.vars.palette.fill.faint,
                    transition: "background-color 0.15s",
                    opacity: selectionMode && !selectable ? 0.58 : 1,
                    "&:hover": {
                        backgroundColor: theme.vars.palette.fill.faintHover,
                    },
                    ...theme.applyStyles("light", {
                        backgroundColor: "#FFFFFF",
                        "&:hover": { backgroundColor: "#FFFFFF" },
                    }),
                })}
            >
                {selectionMode && (
                    <Box
                        sx={{
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            width: 24,
                            flexShrink: 0,
                            color: selected ? "primary.main" : "text.faint",
                        }}
                    >
                        {selectable ? (
                            selected ? (
                                <CheckCircleRoundedIcon sx={{ fontSize: 22 }} />
                            ) : (
                                <RadioButtonUncheckedRoundedIcon
                                    sx={{ fontSize: 22 }}
                                />
                            )
                        ) : null}
                    </Box>
                )}

                {/* Type icon — colored per type in rounded square */}
                <Box
                    sx={{
                        position: "relative",
                        width: 52,
                        height: 52,
                        flexShrink: 0,
                    }}
                >
                    <Box
                        sx={{
                            position: "relative",
                            zIndex: 1,
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            width: 40,
                            height: 40,
                            m: "6px",
                            borderRadius:
                                item.type === "file" ? "12px" : "10px",
                            backgroundColor: iconBgColor(item),
                        }}
                    >
                        {itemIcon(item)}
                    </Box>
                    {isIncomingShared && !selectionMode && (
                        <Box
                            sx={(theme) => ({
                                position: "absolute",
                                right: 1,
                                bottom: 6,
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "center",
                                width: 18,
                                height: 18,
                                borderRadius: "50%",
                                backgroundColor: theme.vars.palette.fill.faint,
                                p: "1px",
                                zIndex: 2,
                            })}
                        >
                            <HugeiconsIcon
                                icon={CircleArrowDownLeftIcon}
                                size={16}
                                strokeWidth={2}
                                color="rgba(16, 113, 255, 1)"
                                style={{ zIndex: 3 }}
                            />
                        </Box>
                    )}
                </Box>

                <Box sx={{ flex: 1, minWidth: 0 }}>
                    <Typography
                        variant="body"
                        sx={{ fontWeight: "regular", lineHeight: 1.45 }}
                        noWrap
                    >
                        {title}
                    </Typography>
                </Box>

                {selectionMode ? null : isTrashView ? (
                    <TrashActions
                        item={item}
                        onRestore={onRestore}
                        onPermanentlyDelete={onPermanentlyDelete}
                    />
                ) : (
                    <Stack
                        direction="row"
                        sx={{ gap: 1, alignItems: "center", flexShrink: 0 }}
                        data-no-long-press="true"
                        onClick={(e) => e.stopPropagation()}
                    >
                        {item.type === "file" && downloading && (
                            <Box
                                sx={{
                                    width: 24,
                                    height: 24,
                                    display: "flex",
                                    alignItems: "center",
                                    justifyContent: "center",
                                }}
                            >
                                <CircularProgress
                                    variant={
                                        downloadProgress !== null
                                            ? "determinate"
                                            : "indeterminate"
                                    }
                                    value={downloadProgress ?? undefined}
                                    sx={(theme) => ({
                                        color: theme.vars.palette.primary.main,
                                    })}
                                    size={20}
                                    thickness={5}
                                />
                            </Box>
                        )}
                        {!isIncomingShared && (
                            <ItemOverflowMenu
                                item={item}
                                onEdit={onEdit}
                                onDelete={onDelete}
                                deleteDisabledHint={deleteDisabledHint}
                                onShareLink={onShareLink}
                            />
                        )}
                    </Stack>
                )}
            </ButtonBase>

            <Snackbar
                open={downloadError}
                message={t("downloadFailed")}
                autoHideDuration={2000}
                onClose={() => {
                    setDownloadError(false);
                }}
            />
        </>
    );
});

// ---------------------------------------------------------------------------
// Overflow menu for item actions
// ---------------------------------------------------------------------------

const ItemOverflowMenu: React.FC<{
    item: LockerItem;
    onEdit?: (item: LockerItem) => void;
    onDelete?: (item: LockerItem) => void;
    deleteDisabledHint?: string;
    onShareLink?: (item: LockerItem) => void;
}> = ({ item, onEdit, onDelete, deleteDisabledHint, onShareLink }) => (
    <OverflowMenu
        ariaID={`item-menu-${item.id}`}
        triggerButtonIcon={<MoreVertIcon sx={{ fontSize: 20 }} />}
        triggerButtonSxProps={{ color: "text.faint", p: 0.5 }}
    >
        {onEdit && (
            <OverflowMenuOption
                startIcon={<EditOutlinedIcon />}
                onClick={() => onEdit(item)}
            >
                {t("edit")}
            </OverflowMenuOption>
        )}
        {onShareLink && (
            <OverflowMenuOption
                startIcon={<ShareOutlinedIcon />}
                onClick={() => onShareLink(item)}
            >
                {t("share")}
            </OverflowMenuOption>
        )}
        {onDelete ? (
            <OverflowMenuOption
                startIcon={<DeleteOutlinedIcon />}
                color="critical"
                onClick={() => onDelete(item)}
            >
                {t("delete")}
            </OverflowMenuOption>
        ) : (
            deleteDisabledHint && (
                <OverflowMenuOption
                    startIcon={<DeleteOutlinedIcon />}
                    color="critical"
                    disabled
                    onClick={() => undefined}
                >
                    {t("delete")}
                </OverflowMenuOption>
            )
        )}
    </OverflowMenu>
);

// ---------------------------------------------------------------------------
// Trash-specific actions
// ---------------------------------------------------------------------------

const TrashActions: React.FC<{
    item: LockerItem;
    onRestore?: (item: LockerItem) => void;
    onPermanentlyDelete?: (items: LockerItem[]) => void;
}> = ({ item, onRestore, onPermanentlyDelete }) => (
    <Stack
        direction="row"
        sx={{ gap: 0, flexShrink: 0 }}
        onClick={(e) => e.stopPropagation()}
    >
        {onRestore && (
            <Tooltip title={t("restore")}>
                <IconButton
                    size="small"
                    onClick={() => onRestore(item)}
                    sx={{ color: "text.faint" }}
                >
                    <RestoreIcon sx={{ fontSize: 20 }} />
                </IconButton>
            </Tooltip>
        )}
        {onPermanentlyDelete && (
            <Tooltip title={t("permanentlyDelete")}>
                <IconButton
                    size="small"
                    onClick={() => onPermanentlyDelete([item])}
                    sx={{ color: "critical.main" }}
                >
                    <DeleteOutlinedIcon sx={{ fontSize: 20 }} />
                </IconButton>
            </Tooltip>
        )}
    </Stack>
);

/**
 * Background color for the icon square, per item type.
 */
const iconBgColor = (item: LockerItem): string => {
    return lockerItemIconConfig(
        item.type,
        item.type === "file" ? (item.data as GenericFileData).name : undefined,
    ).backgroundColor;
};

/** Icon for a LockerItem. */
const itemIcon = (item: LockerItem) => {
    return lockerItemIcon(item.type, {
        fileName:
            item.type === "file"
                ? (item.data as GenericFileData).name
                : undefined,
        size: item.type === "file" ? 24 : 20,
        strokeWidth: 1.9,
    });
};
