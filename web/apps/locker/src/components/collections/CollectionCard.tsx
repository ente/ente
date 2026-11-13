import {
    lockerColorSx,
    lockerTextBodySx,
    lockerTextMiniSx,
} from "@/styles/tokens";
import type { LockerCollection } from "@/types";
import { isImportantCollection } from "@/types";
import { Link01Icon, StarIcon, Wallet05Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, ButtonBase, Stack, Typography } from "@mui/material";
import { t } from "i18next";
import React from "react";

import { CollectionContextMenu } from "./CollectionContextMenu";

export const CollectionCard: React.FC<{
    collection: LockerCollection;
    onClick: () => void;
    onShare?: () => void;
    onLeave?: () => void;
    onRename?: () => void;
    onDelete?: () => void;
}> = ({ collection, onClick, onShare, onLeave, onRename, onDelete }) => {
    return (
        <ButtonBase
            component="div"
            onClick={onClick}
            sx={(theme) => ({
                width: "100%",
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                gap: 1.5,
                pl: 1.5,
                pr: 0,
                py: 1.5,
                borderRadius: "20px",
                border: "1.5px solid",
                transition: "background-color 0.15s, border-color 0.15s",
                ...lockerColorSx(theme, {
                    backgroundColor: "fillLight",
                    borderColor: "fillLight",
                }),
                "&:hover": {
                    ...lockerColorSx(theme, { backgroundColor: "fillHover" }),
                },
            })}
        >
            <Stack
                direction="row"
                sx={{ flex: 1, minWidth: 0, alignItems: "center", gap: 1.25 }}
            >
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
                    {isImportantCollection(collection) ? (
                        <Box
                            sx={(theme) => ({
                                display: "flex",
                                ...lockerColorSx(theme, { color: "primary" }),
                            })}
                        >
                            <HugeiconsIcon
                                icon={StarIcon}
                                size={24}
                                strokeWidth={1.5}
                            />
                        </Box>
                    ) : (
                        <Box
                            sx={(theme) => ({
                                display: "flex",
                                ...lockerColorSx(theme, { color: "textBase" }),
                            })}
                        >
                            <HugeiconsIcon
                                icon={Wallet05Icon}
                                size={24}
                                strokeWidth={1.5}
                            />
                        </Box>
                    )}
                    {collection.isShared && <SharedCollectionBadge />}
                </Box>
                <Box sx={{ flex: 1, minWidth: 0 }}>
                    <Typography
                        sx={(theme) => ({
                            ...lockerTextBodySx,
                            minWidth: 0,
                            ...lockerColorSx(theme, { color: "textBase" }),
                        })}
                        noWrap
                    >
                        {collection.name}
                    </Typography>
                    <Typography
                        sx={(theme) => ({
                            ...lockerTextMiniSx,
                            mt: "4px",
                            ...lockerColorSx(theme, { color: "textLight" }),
                        })}
                    >
                        {t("lockerItemsCount", {
                            count: collection.items.length,
                        })}
                    </Typography>
                </Box>
            </Stack>
            <Box
                sx={{
                    flexShrink: 0,
                    mr: 1.5,
                    width: 44,
                    height: 24,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "flex-end",
                }}
                onClick={(event) => event.stopPropagation()}
            >
                {(onShare || onLeave || onRename || onDelete) && (
                    <CollectionContextMenu
                        ariaID={`collection-context-menu-${collection.id}`}
                        onShare={onShare}
                        onLeave={onLeave}
                        onRename={onRename}
                        onDelete={onDelete}
                    />
                )}
            </Box>
        </ButtonBase>
    );
};

const SharedCollectionBadge: React.FC = () => {
    return (
        <Box
            sx={(theme) => ({
                position: "absolute",
                right: -4,
                bottom: -4,
                width: 18,
                height: 18,
                borderRadius: "50%",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                ...lockerColorSx(theme, {
                    backgroundColor: "fillLight",
                    color: "primary",
                }),
            })}
        >
            <HugeiconsIcon icon={Link01Icon} size={12} strokeWidth={2} />
        </Box>
    );
};
