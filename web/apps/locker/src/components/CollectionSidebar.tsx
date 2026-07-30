import type { LockerCollection } from "@/types";
import { isImportantCollection, visibleLockerCollections } from "@/types";
import CloudQueueOutlinedIcon from "@mui/icons-material/CloudQueueOutlined";
import DeleteOutlinedIcon from "@mui/icons-material/DeleteOutlined";
import GridViewOutlinedIcon from "@mui/icons-material/GridViewOutlined";
import HomeOutlinedIcon from "@mui/icons-material/HomeOutlined";
import LabelOutlinedIcon from "@mui/icons-material/LabelOutlined";
import LogoutOutlinedIcon from "@mui/icons-material/LogoutOutlined";
import StarIcon from "@mui/icons-material/Star";
import {
    Badge,
    Box,
    Divider,
    List,
    ListItemButton,
    ListItemIcon,
    ListItemText,
    Stack,
    Typography,
} from "@mui/material";
import { useBaseContext } from "ente-base/context";
import { t } from "i18next";
import React, { useMemo } from "react";

/** Width of the sidebar on desktop. */
export const SIDEBAR_WIDTH = 280;

interface CollectionSidebarProps {
    collections: LockerCollection[];
    selectedCollectionID: number | null;
    isTrashView: boolean;
    isCollectionsView: boolean;
    onSelectCollection: (collectionID: number | null) => void;
    onSelectCollections: () => void;
    onSelectTrash: () => void;
    trashItemCount: number;
    userDetails?: {
        email: string;
        usage: number;
        storageLimit: number;
        fileCount: number;
        lockerFileLimit: number;
    };
}

export const CollectionSidebar: React.FC<CollectionSidebarProps> = ({
    collections,
    selectedCollectionID,
    isTrashView,
    isCollectionsView,
    onSelectCollection,
    onSelectCollections,
    onSelectTrash,
    trashItemCount,
    userDetails,
}) => {
    const { logout } = useBaseContext();
    const displayCollections = useMemo(
        () => visibleLockerCollections(collections),
        [collections],
    );

    const totalItems = collections.reduce((sum, c) => sum + c.items.length, 0);
    const isHomeSelected =
        !isTrashView && !isCollectionsView && selectedCollectionID === null;
    const usageLimit = userDetails
        ? Math.max(userDetails.lockerFileLimit, 1)
        : 100;
    const usageProgress = userDetails
        ? Math.min((userDetails.fileCount / usageLimit) * 100, 100)
        : 0;
    const formattedUsage = new Intl.NumberFormat().format(
        userDetails?.fileCount ?? 0,
    );
    const formattedUsageLimit = new Intl.NumberFormat().format(usageLimit);

    return (
        <Box
            sx={{
                width: SIDEBAR_WIDTH,
                flexShrink: 0,
                display: "flex",
                flexDirection: "column",
                borderRight: 1,
                borderColor: "divider",
                backgroundColor: "background.paper",
                height: "calc(100vh - 72px)",
            }}
        >
            <Stack sx={{ px: 1.5, py: 2, gap: 2, flex: 1, minHeight: 0 }}>
                {userDetails && (
                    <Box sx={{ px: 0.5 }}>
                        {userDetails.email && (
                            <Typography
                                variant="small"
                                sx={{
                                    color: "text.muted",
                                    mb: 1.25,
                                    display: "block",
                                    wordBreak: "break-all",
                                }}
                            >
                                {userDetails.email}
                            </Typography>
                        )}

                        <Box
                            sx={{
                                p: 1.5,
                                borderRadius: "18px",
                                background:
                                    "linear-gradient(135deg, #1071FF 0%, #0056CC 100%)",
                                color: "#fff",
                            }}
                        >
                            <Stack
                                direction="row"
                                sx={{ gap: 1.5, alignItems: "center" }}
                            >
                                <Box
                                    sx={{
                                        width: 40,
                                        height: 40,
                                        borderRadius: "12px",
                                        backgroundColor:
                                            "rgba(255, 255, 255, 0.1)",
                                        display: "flex",
                                        alignItems: "center",
                                        justifyContent: "center",
                                        flexShrink: 0,
                                    }}
                                >
                                    <CloudQueueOutlinedIcon
                                        sx={{ fontSize: 20 }}
                                    />
                                </Box>
                                <Stack sx={{ gap: 1, flex: 1, minWidth: 0 }}>
                                    <Stack
                                        direction="row"
                                        sx={{
                                            alignItems: "baseline",
                                            justifyContent: "space-between",
                                            gap: 1,
                                        }}
                                    >
                                        <Typography
                                            variant="small"
                                            sx={{
                                                fontWeight: "bold",
                                                color: "#fff",
                                            }}
                                        >
                                            {t("usage")}
                                        </Typography>
                                        <Typography
                                            variant="mini"
                                            sx={{
                                                color: "rgba(255,255,255,0.72)",
                                                whiteSpace: "nowrap",
                                            }}
                                        >
                                            {t("lockerUsageSummary", {
                                                used: formattedUsage,
                                                total: formattedUsageLimit,
                                            })}
                                        </Typography>
                                    </Stack>
                                    <Box
                                        sx={{
                                            height: 4,
                                            borderRadius: 999,
                                            backgroundColor:
                                                "rgba(255,255,255,0.22)",
                                            overflow: "hidden",
                                        }}
                                    >
                                        <Box
                                            sx={{
                                                width: `${usageProgress}%`,
                                                minWidth:
                                                    usageProgress > 0 ? 8 : 0,
                                                height: "100%",
                                                borderRadius: 999,
                                                backgroundColor: "#fff",
                                            }}
                                        />
                                    </Box>
                                </Stack>
                            </Stack>
                        </Box>
                    </Box>
                )}

                <Divider />

                <List disablePadding sx={{ gap: 0.5, display: "grid" }}>
                    <SidebarRow
                        label={t("home")}
                        icon={<HomeOutlinedIcon fontSize="small" />}
                        badgeContent={totalItems}
                        selected={isHomeSelected}
                        onClick={() => onSelectCollection(null)}
                    />
                    <SidebarRow
                        label={t("menuCollections")}
                        icon={<GridViewOutlinedIcon fontSize="small" />}
                        badgeContent={displayCollections.length}
                        selected={isCollectionsView}
                        onClick={onSelectCollections}
                    />
                    <SidebarRow
                        label={t("menuTrash")}
                        icon={<DeleteOutlinedIcon fontSize="small" />}
                        badgeContent={trashItemCount}
                        selected={isTrashView}
                        onClick={onSelectTrash}
                    />
                </List>

                <Divider />

                <Box sx={{ px: 1 }}>
                    <Typography
                        variant="mini"
                        sx={{
                            color: "text.faint",
                            textTransform: "uppercase",
                            letterSpacing: "0.08em",
                            fontWeight: "bold",
                        }}
                    >
                        {t("collections")}
                    </Typography>
                </Box>

                <Box sx={{ flex: 1, minHeight: 0, overflowY: "auto", pr: 0.5 }}>
                    <List disablePadding sx={{ gap: 0.5, display: "grid" }}>
                        {displayCollections.map((collection) => (
                            <SidebarRow
                                key={collection.id}
                                label={collection.name}
                                icon={
                                    isImportantCollection(collection) ? (
                                        <StarIcon
                                            fontSize="small"
                                            sx={{ color: "primary.main" }}
                                        />
                                    ) : (
                                        <LabelOutlinedIcon fontSize="small" />
                                    )
                                }
                                badgeContent={collection.items.length}
                                selected={
                                    !isTrashView &&
                                    !isCollectionsView &&
                                    selectedCollectionID === collection.id
                                }
                                onClick={() =>
                                    onSelectCollection(collection.id)
                                }
                            />
                        ))}
                    </List>
                </Box>
            </Stack>

            <Box
                sx={{
                    px: 2,
                    pt: 1.25,
                    pb: 2,
                    borderTop: 1,
                    borderColor: "divider",
                    backgroundColor: "background.paper",
                }}
            >
                <SidebarRow
                    label={t("logout")}
                    icon={<LogoutOutlinedIcon fontSize="small" />}
                    selected={false}
                    onClick={logout}
                    color="critical.main"
                />
            </Box>
        </Box>
    );
};

const SidebarRow: React.FC<{
    label: string;
    icon: React.ReactNode;
    badgeContent?: number;
    selected: boolean;
    onClick: () => void;
    color?: string;
}> = ({ label, icon, badgeContent, selected, onClick, color }) => (
    <ListItemButton
        selected={selected}
        onClick={onClick}
        sx={(theme) => ({
            borderRadius: 2,
            px: 1.25,
            color,
            border: "1px solid transparent",
            ...(selected && {
                color: color ?? "primary.main",
                borderColor: theme.vars.palette.primary.main,
                backgroundColor: "rgba(16, 113, 255, 0.10)",
            }),
            "&.Mui-selected": { backgroundColor: "rgba(16, 113, 255, 0.10)" },
            "&.Mui-selected:hover": {
                backgroundColor: "rgba(16, 113, 255, 0.14)",
            },
            "&:hover": {
                backgroundColor: selected
                    ? "rgba(16, 113, 255, 0.14)"
                    : theme.vars.palette.fill.faint,
            },
        })}
    >
        <ListItemIcon sx={{ minWidth: 36, color: "inherit" }}>
            {icon}
        </ListItemIcon>
        <ListItemText
            primary={label}
            slotProps={{
                primary: {
                    variant: "body",
                    noWrap: true,
                    sx: { fontWeight: selected ? "bold" : "medium" },
                },
            }}
        />
        {typeof badgeContent === "number" && (
            <Badge
                badgeContent={badgeContent}
                color={selected ? "primary" : "default"}
                max={999}
                sx={{ mr: 1 }}
            />
        )}
    </ListItemButton>
);
