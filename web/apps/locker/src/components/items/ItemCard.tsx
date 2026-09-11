import { lockerItemIcon } from "@/components/items/locker-item-icons";
import {
    LockerMenuOption,
    LockerOverflowMenu,
} from "@/components/ui/LockerMenu";
import { downloadLockerFile } from "@/services/download";
import type { GenericFileData, LockerItem } from "@/types";
import { getItemTitle, hasDownloadableObject } from "@/types";
import {
    ArrowReloadHorizontalIcon,
    CircleArrowDownLeftIcon,
    Delete02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import CheckCircleRoundedIcon from "@mui/icons-material/CheckCircleRounded";
import DeleteOutlinedIcon from "@mui/icons-material/DeleteOutlined";
import EditOutlinedIcon from "@mui/icons-material/EditOutlined";
import MoreVertIcon from "@mui/icons-material/MoreVert";
import RadioButtonUncheckedRoundedIcon from "@mui/icons-material/RadioButtonUncheckedRounded";
import ShareOutlinedIcon from "@mui/icons-material/ShareOutlined";
import {
    Box,
    ButtonBase,
    CircularProgress,
    Snackbar,
    Stack,
    Typography,
} from "@mui/material";
import log from "ente-base/log";
import { t } from "i18next";
import React, { useCallback, useState } from "react";
import {
    lockerColors,
    lockerColorSx,
    lockerTextBodySx,
} from "../../styles/tokens";

interface ItemCardProps {
    item: LockerItem;
    onClick: () => void;
    isTrashView?: boolean;
    isIncomingShared?: boolean;
    onEdit?: (item: LockerItem) => void;
    onDelete?: (item: LockerItem) => void;
    deleteDisabledHint?: string;
    onPermanentlyDelete?: (items: LockerItem[]) => void;
    onRestore?: (item: LockerItem) => void;
    onShareLink?: (item: LockerItem) => void;
    selectionMode?: boolean;
    selectable?: boolean;
    selected?: boolean;
    onToggleSelection?: (item: LockerItem) => void;
    onLongPressSelect?: (item: LockerItem) => void;
}

export const ItemCard: React.FC<ItemCardProps> = React.memo(function ItemCard({
    item,
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
        if (downloading || !hasDownloadableObject(item)) return;
        setDownloading(true);
        setDownloadProgress(null);
        try {
            const fileName = getItemTitle(item);
            await downloadLockerFile(item.id, fileName, ({ loaded, total }) => {
                if (total && total > 0) {
                    setDownloadProgress(
                        Math.min(100, Math.round((loaded / total) * 100)),
                    );
                }
            });
        } catch (e) {
            log.error(`Failed to download file ${item.id}`, e);
            setDownloadError(true);
        } finally {
            setDownloading(false);
            setDownloadProgress(null);
        }
    }, [item, downloading]);

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
                    if (!isTrashView && item.type === "file" && downloadable) {
                        void handleDownload();
                        return;
                    }
                    onClick();
                }}
                sx={(theme) => ({
                    display: "flex",
                    width: "100%",
                    textAlign: "left",
                    borderRadius: "20px",
                    overflow: "hidden",
                    p: 1.5,
                    gap: 1.5,
                    alignItems: "center",
                    ...lockerColorSx(theme, { backgroundColor: "fillLight" }),
                    transition: "background-color 0.15s",
                    opacity: selectionMode && !selectable ? 0.58 : 1,
                    "&:hover": {
                        ...lockerColorSx(theme, {
                            backgroundColor: "fillHover",
                        }),
                    },
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

                <Box
                    sx={(theme) => ({
                        position: "relative",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        width: 40,
                        height: 40,
                        flexShrink: 0,
                        borderRadius: "12px",
                        ...lockerColorSx(theme, {
                            backgroundColor: "backgroundBase",
                        }),
                    })}
                >
                    {itemIcon(item)}
                    {isIncomingShared && !selectionMode && (
                        <Box
                            sx={(theme) => ({
                                position: "absolute",
                                right: -4,
                                bottom: -4,
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "center",
                                width: 18,
                                height: 18,
                                borderRadius: "50%",
                                ...lockerColorSx(theme, {
                                    backgroundColor: "fillLight",
                                }),
                            })}
                        >
                            <HugeiconsIcon
                                icon={CircleArrowDownLeftIcon}
                                size={16}
                                strokeWidth={2}
                                color={lockerColors.primary.dark}
                            />
                        </Box>
                    )}
                </Box>

                <Box sx={{ flex: 1, minWidth: 0 }}>
                    <Typography variant="body" sx={lockerTextBodySx} noWrap>
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

const ItemOverflowMenu: React.FC<{
    item: LockerItem;
    onEdit?: (item: LockerItem) => void;
    onDelete?: (item: LockerItem) => void;
    deleteDisabledHint?: string;
    onShareLink?: (item: LockerItem) => void;
}> = ({ item, onEdit, onDelete, deleteDisabledHint, onShareLink }) => (
    <LockerOverflowMenu
        ariaID={`item-menu-${item.id}`}
        triggerButtonIcon={<MoreVertIcon sx={{ fontSize: 20 }} />}
        triggerButtonSxProps={(theme) => ({
            width: 40,
            height: 40,
            p: 0,
            ...lockerColorSx(theme, { color: "textLight" }),
        })}
    >
        {onEdit && (
            <LockerMenuOption
                startIcon={<EditOutlinedIcon />}
                onClick={() => onEdit(item)}
            >
                {t("edit")}
            </LockerMenuOption>
        )}
        {onShareLink && (
            <LockerMenuOption
                startIcon={<ShareOutlinedIcon />}
                onClick={() => onShareLink(item)}
            >
                {t("share")}
            </LockerMenuOption>
        )}
        {onDelete ? (
            <LockerMenuOption
                startIcon={<DeleteOutlinedIcon />}
                critical
                onClick={() => onDelete(item)}
            >
                {t("delete")}
            </LockerMenuOption>
        ) : (
            deleteDisabledHint && (
                <LockerMenuOption
                    startIcon={<DeleteOutlinedIcon />}
                    critical
                    disabled
                    onClick={() => undefined}
                >
                    {t("delete")}
                </LockerMenuOption>
            )
        )}
    </LockerOverflowMenu>
);

const TrashActions: React.FC<{
    item: LockerItem;
    onRestore?: (item: LockerItem) => void;
    onPermanentlyDelete?: (items: LockerItem[]) => void;
}> = ({ item, onRestore, onPermanentlyDelete }) => (
    <Stack
        direction="row"
        sx={{ gap: 0, flexShrink: 0 }}
        data-no-long-press="true"
        onClick={(e) => e.stopPropagation()}
    >
        <LockerOverflowMenu
            ariaID={`trash-item-menu-${item.id}`}
            triggerButtonIcon={<MoreVertIcon sx={{ fontSize: 20 }} />}
            triggerButtonSxProps={(theme) => ({
                width: 40,
                height: 40,
                p: 0,
                ...lockerColorSx(theme, { color: "textLight" }),
            })}
        >
            {onRestore && (
                <LockerMenuOption
                    onClick={() => onRestore(item)}
                    startIcon={
                        <HugeiconsIcon
                            icon={ArrowReloadHorizontalIcon}
                            size={18}
                            strokeWidth={1.5}
                        />
                    }
                >
                    {t("restore")}
                </LockerMenuOption>
            )}
            {onPermanentlyDelete && (
                <LockerMenuOption
                    onClick={() => onPermanentlyDelete([item])}
                    startIcon={
                        <HugeiconsIcon
                            icon={Delete02Icon}
                            size={18}
                            strokeWidth={1.5}
                        />
                    }
                    critical
                >
                    {t("permanentlyDelete")}
                </LockerMenuOption>
            )}
        </LockerOverflowMenu>
    </Stack>
);

const itemIcon = (item: LockerItem) => {
    return lockerItemIcon(item.type, {
        fileName:
            item.type === "file"
                ? (item.data as GenericFileData).name
                : undefined,
        size: 24,
        strokeWidth: 1.5,
    });
};
