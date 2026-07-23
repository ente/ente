import type { LockerCollection } from "@/types";
import { visibleLockerCollections } from "@/types";
import {
    Delete02Icon,
    FavouriteIcon,
    HelpCircleIcon,
    Home01Icon,
    InformationCircleIcon,
    Logout05Icon,
    UserIcon,
    Wallet05Icon,
} from "@hugeicons/core-free-icons";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import CloseIcon from "@mui/icons-material/Close";
import { Box, IconButton, Stack, Typography, useTheme } from "@mui/material";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { useBaseContext } from "ente-base/context";
import {
    mergeLegacySuggestedUsers,
    type LegacySuggestedUser,
} from "ente-contacts-web/legacy";
import { t } from "i18next";
import dynamic from "next/dynamic";
import React, { useEffect, useMemo, useState } from "react";
import { LockerAboutDrawer } from "./LockerAboutDrawer";
import { LockerAccountDrawer } from "./LockerAccountDrawer";
import { LockerAuthenticateUser } from "./LockerAuthenticateUser";
import { LockerSidebarCardButton } from "./LockerSidebarCardButton";
import { LockerSidebarDrawer } from "./LockerSidebarShell";
import { LockerSocialFooter } from "./LockerSocialFooter";
import { LockerSupportDrawer } from "./LockerSupportDrawer";

const LockerLegacyDrawer = dynamic(
    () =>
        import("./LockerLegacyDrawer").then(
            ({ LockerLegacyDrawer }) => LockerLegacyDrawer,
        ),
    { ssr: false },
);

interface LockerSidebarProps {
    open: boolean;
    onClose: () => void;
    collections: LockerCollection[];
    trashItemCount: number;
    onSelectHome: () => void;
    onSelectCollections: () => void;
    onSelectTrash: () => void;
    isHomeView: boolean;
    isTrashView: boolean;
    isCollectionsView: boolean;
    userDetails?: {
        email: string;
        usage: number;
        storageLimit: number;
        fileCount: number;
        lockerFileLimit: number;
        isPartOfFamily: boolean;
        lockerFamilyFileCount?: number;
    };
}

/**
 * Left sidebar drawer for the Locker web app.
 *
 * Shows user info, storage usage, collections, trash, help & support,
 * about section, and logout.
 */
export const LockerSidebar: React.FC<LockerSidebarProps> = ({
    open,
    onClose,
    collections,
    trashItemCount,
    onSelectHome,
    onSelectCollections,
    onSelectTrash,
    isHomeView,
    isTrashView,
    isCollectionsView,
    userDetails,
}) => {
    const { logout } = useBaseContext();
    const theme = useTheme();
    const displayCollections = visibleLockerCollections(collections);
    const totalItems = collections.reduce(
        (sum, collection) => sum + collection.items.length,
        0,
    );
    const [isAccountOpen, setIsAccountOpen] = useState(false);
    const [isLegacyAuthenticateOpen, setIsLegacyAuthenticateOpen] =
        useState(false);
    const [isLegacyOpen, setIsLegacyOpen] = useState(false);
    const [isSupportOpen, setIsSupportOpen] = useState(false);
    const [isAboutOpen, setIsAboutOpen] = useState(false);
    const legacySuggestedUsers = useMemo(() => {
        const participants: LegacySuggestedUser[] = collections.flatMap(
            (collection) =>
                [collection.owner, ...collection.sharees]
                    .filter(
                        (
                            participant,
                        ): participant is { id: number; email: string } =>
                            !!participant.email?.trim(),
                    )
                    .map((participant) => ({
                        id: participant.id,
                        email: participant.email,
                    })),
        );
        return mergeLegacySuggestedUsers(participants);
    }, [collections]);

    const maxFileCount = userDetails
        ? Math.max(userDetails.lockerFileLimit, 1)
        : 1;
    const userProgress = userDetails
        ? Math.min(userDetails.fileCount / maxFileCount, 1)
        : 0;
    const showFamilyBreakup =
        !!userDetails &&
        userDetails.isPartOfFamily &&
        typeof userDetails.lockerFamilyFileCount === "number";
    const familyProgress = showFamilyBreakup
        ? Math.min((userDetails.lockerFamilyFileCount ?? 0) / maxFileCount, 1)
        : 0;
    const formattedUsed = new Intl.NumberFormat().format(
        userDetails?.fileCount ?? 0,
    );
    const formattedMax = new Intl.NumberFormat().format(maxFileCount);

    useEffect(() => {
        if (!open) {
            setIsAccountOpen(false);
            setIsLegacyAuthenticateOpen(false);
            setIsLegacyOpen(false);
            setIsSupportOpen(false);
            setIsAboutOpen(false);
        }
    }, [open]);

    return (
        <>
            <LockerSidebarDrawer open={open} onClose={onClose} anchor="left">
                <Stack
                    sx={{
                        height: "calc(100dvh - env(titlebar-area-height, 0px) - 16px)",
                        minHeight: 0,
                        backgroundColor: "background.default",
                        ...theme.applyStyles("dark", {
                            backgroundColor: "background.paper",
                        }),
                    }}
                >
                    <Box
                        sx={{
                            flex: 1,
                            minHeight: 0,
                            overflowY: "auto",
                            overscrollBehavior: "contain",
                            WebkitOverflowScrolling: "touch",
                        }}
                    >
                        {/* Header */}
                        <Stack sx={{ px: 1, pt: 0.5, pb: 0.5 }}>
                            <Stack
                                direction="row"
                                sx={{
                                    alignItems: "center",
                                    justifyContent: "space-between",
                                }}
                            >
                                <Box
                                    sx={{
                                        px: 1,
                                        lineHeight: 0,
                                        color: "#111111",
                                        ...theme.applyStyles("dark", {
                                            color: "rgba(255,255,255,0.92)",
                                        }),
                                    }}
                                >
                                    <EnteLogo height={18} />
                                </Box>
                                <IconButton onClick={onClose} color="secondary">
                                    <CloseIcon />
                                </IconButton>
                            </Stack>
                        </Stack>

                        {userDetails?.email && (
                            <Typography
                                variant="small"
                                sx={{
                                    px: 2,
                                    pb: 1,
                                    color: "text.muted",
                                    wordBreak: "break-all",
                                }}
                            >
                                {userDetails.email}
                            </Typography>
                        )}

                        {userDetails && (
                            <Box
                                sx={{
                                    mx: 1.5,
                                    mb: 1.5,
                                    p: 2,
                                    borderRadius: "20px",
                                    color: "rgba(255,255,255,0.92)",
                                    background:
                                        "radial-gradient(circle at 12px 12px, rgba(255,255,255,0.03) 0 2px, transparent 2px) 0 0 / 24px 24px, linear-gradient(180deg, #2B2B2B 0%, #151515 100%)",
                                    overflow: "hidden",
                                }}
                            >
                                <Typography
                                    variant="small"
                                    sx={{
                                        color: "rgba(255,255,255,0.68)",
                                        mb: 0.5,
                                        display: "block",
                                        fontSize: 16,
                                        lineHeight: "20px",
                                    }}
                                >
                                    {t("itemsStored")}
                                </Typography>
                                <Typography
                                    sx={{
                                        mb: 2,
                                        display: "block",
                                        fontSize: 32,
                                        lineHeight: "39px",
                                        fontWeight: 500,
                                    }}
                                >
                                    {formattedUsed}
                                    <Box
                                        component="span"
                                        sx={{
                                            color: "rgba(255,255,255,0.68)",
                                            fontWeight: 500,
                                        }}
                                    >
                                        {` ${t("of_")} `}
                                    </Box>
                                    {formattedMax}
                                </Typography>
                                <Box
                                    sx={{
                                        position: "relative",
                                        height: 8,
                                        borderRadius: 999,
                                        bgcolor: "rgba(193, 193, 193, 0.11)",
                                        overflow: "hidden",
                                    }}
                                >
                                    {showFamilyBreakup && (
                                        <Box
                                            sx={{
                                                position: "absolute",
                                                inset: 0,
                                                width: `${familyProgress * 100}%`,
                                                borderRadius: 999,
                                                bgcolor:
                                                    "rgba(255,255,255,0.92)",
                                            }}
                                        />
                                    )}
                                    <Box
                                        sx={{
                                            position: "absolute",
                                            inset: 0,
                                            width: `${userProgress * 100}%`,
                                            borderRadius: 999,
                                            bgcolor: "#1071FF",
                                        }}
                                    />
                                </Box>
                                {showFamilyBreakup ? (
                                    <Stack
                                        direction="row"
                                        sx={{
                                            gap: 2,
                                            mt: 1.5,
                                            alignItems: "center",
                                            color: "rgba(255,255,255,0.92)",
                                        }}
                                    >
                                        <Stack
                                            direction="row"
                                            sx={{
                                                gap: 0.75,
                                                alignItems: "center",
                                            }}
                                        >
                                            <Box
                                                sx={{
                                                    width: 8,
                                                    height: 8,
                                                    borderRadius: "50%",
                                                    bgcolor: "#1071FF",
                                                }}
                                            />
                                            <Typography
                                                variant="mini"
                                                sx={{
                                                    color: "inherit",
                                                    fontWeight: "bold",
                                                }}
                                            >
                                                {t("usageYou")}
                                            </Typography>
                                        </Stack>
                                        <Stack
                                            direction="row"
                                            sx={{
                                                gap: 0.75,
                                                alignItems: "center",
                                            }}
                                        >
                                            <Box
                                                sx={{
                                                    width: 8,
                                                    height: 8,
                                                    borderRadius: "50%",
                                                    bgcolor:
                                                        "rgba(255,255,255,0.92)",
                                                }}
                                            />
                                            <Typography
                                                variant="mini"
                                                sx={{
                                                    color: "inherit",
                                                    fontWeight: "bold",
                                                }}
                                            >
                                                {t("usageFamily")}
                                            </Typography>
                                        </Stack>
                                    </Stack>
                                ) : (
                                    <Box sx={{ height: 4 }} />
                                )}
                            </Box>
                        )}

                        <Box sx={{ px: 0.5, mt: 0.5 }}>
                            <Stack sx={{ gap: 1 }}>
                                <LockerSidebarCardButton
                                    icon={Home01Icon}
                                    label={t("home")}
                                    caption={String(totalItems)}
                                    selected={isHomeView}
                                    onClick={onSelectHome}
                                />
                                <LockerSidebarCardButton
                                    icon={Wallet05Icon}
                                    label={t("menuCollections")}
                                    caption={String(displayCollections.length)}
                                    selected={isCollectionsView}
                                    onClick={onSelectCollections}
                                />
                                <LockerSidebarCardButton
                                    icon={Delete02Icon}
                                    label={t("menuTrash")}
                                    caption={String(trashItemCount)}
                                    selected={isTrashView}
                                    onClick={onSelectTrash}
                                />
                            </Stack>
                        </Box>
                        <Box
                            sx={{
                                mx: 1.5,
                                mt: 2,
                                borderTop: 1,
                                borderColor: "divider",
                            }}
                        />

                        <Box sx={{ px: 0.5, mt: 2, pb: 1 }}>
                            <Stack sx={{ gap: 1 }}>
                                <LockerSidebarCardButton
                                    icon={UserIcon}
                                    label={t("account")}
                                    endIcon={<ChevronRightIcon />}
                                    onClick={() => setIsAccountOpen(true)}
                                />
                                <LockerSidebarCardButton
                                    icon={FavouriteIcon}
                                    label="Legacy"
                                    endIcon={<ChevronRightIcon />}
                                    onClick={() =>
                                        setIsLegacyAuthenticateOpen(true)
                                    }
                                />
                                <LockerSidebarCardButton
                                    icon={HelpCircleIcon}
                                    label={t("help_and_support")}
                                    endIcon={<ChevronRightIcon />}
                                    onClick={() => setIsSupportOpen(true)}
                                />
                                <LockerSidebarCardButton
                                    icon={InformationCircleIcon}
                                    label={t("about")}
                                    endIcon={<ChevronRightIcon />}
                                    onClick={() => setIsAboutOpen(true)}
                                />
                            </Stack>
                        </Box>
                        <Box
                            sx={{
                                mx: 1.5,
                                mt: 1,
                                borderTop: 1,
                                borderColor: "divider",
                            }}
                        />
                        <Box sx={{ px: 0.5, mt: 2, pb: 1 }}>
                            <Stack sx={{ gap: 1 }}>
                                <LockerSidebarCardButton
                                    icon={Logout05Icon}
                                    label={t("logout")}
                                    color="critical.main"
                                    onClick={logout}
                                />
                            </Stack>
                        </Box>
                    </Box>

                    <Box
                        sx={{
                            pb: "max(8px, env(safe-area-inset-bottom))",
                            flexShrink: 0,
                        }}
                    >
                        <LockerSocialFooter />
                    </Box>
                </Stack>
            </LockerSidebarDrawer>

            <LockerAccountDrawer
                open={isAccountOpen}
                onClose={() => setIsAccountOpen(false)}
                onRootClose={onClose}
            />
            <LockerLegacyDrawer
                open={isLegacyOpen}
                onClose={() => setIsLegacyOpen(false)}
                onRootClose={onClose}
                suggestedUsers={legacySuggestedUsers}
            />
            <LockerAuthenticateUser
                open={isLegacyAuthenticateOpen}
                onClose={() => setIsLegacyAuthenticateOpen(false)}
                onAuthenticate={() => setIsLegacyOpen(true)}
            />
            <LockerSupportDrawer
                open={isSupportOpen}
                onClose={() => setIsSupportOpen(false)}
                onRootClose={onClose}
            />
            <LockerAboutDrawer
                open={isAboutOpen}
                onClose={() => setIsAboutOpen(false)}
                onRootClose={onClose}
            />
        </>
    );
};
