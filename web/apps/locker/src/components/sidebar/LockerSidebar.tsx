import type { LockerCollection } from "@/types";
import {
    Delete02Icon,
    FavouriteIcon,
    HelpCircleIcon,
    InformationCircleIcon,
    Logout05Icon,
    SecurityCheckIcon,
    Sun03Icon,
    UserIcon,
    Wallet05Icon,
} from "@hugeicons/core-free-icons";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import { Box, Stack, Typography } from "@mui/material";
import { useBaseContext } from "ente-base/context";
import {
    mergeLegacySuggestedUsers,
    type LegacySuggestedUser,
} from "ente-contacts/legacy";
import { t } from "i18next";
import dynamic from "next/dynamic";
import React, { useEffect, useMemo, useState } from "react";
import { LockerAuthenticateUser } from "../auth/LockerAuthenticateUser";
import { LockerAboutDrawer } from "./LockerAboutDrawer";
import { LockerAccountDrawer } from "./LockerAccountDrawer";
import { LockerSidebarCardButton } from "./LockerSidebarCardButton";
import {
    LockerSidebarDrawer,
    LockerSidebarTitlebar,
} from "./LockerSidebarShell";
import { LockerSocialFooter } from "./LockerSocialFooter";
import { LockerSupportDrawer } from "./LockerSupportDrawer";
import { LockerThemeDrawer } from "./LockerThemeDrawer";

import { LockerSecurityDrawer } from "./LockerSecurityDrawer";
import {
    familyColor,
    h1Sx,
    largeSx,
    usageBarSx,
    usageCardSx,
    usageMutedSx,
} from "./locker-sidebar-styles";

const legendItems = [
    { key: "usageYou", color: "accent.main" },
    { key: "usageFamily", color: familyColor },
];

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
    onSelectCollections: () => void;
    onSelectTrash: () => void;
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

export const LockerSidebar: React.FC<LockerSidebarProps> = ({
    open,
    onClose,
    collections,
    onSelectCollections,
    onSelectTrash,
    isTrashView,
    isCollectionsView,
    userDetails,
}) => {
    const { logout } = useBaseContext();
    const [isThemeOpen, setIsThemeOpen] = useState(false);
    const [isAccountOpen, setIsAccountOpen] = useState(false);
    const [isLegacyAuthenticateOpen, setIsLegacyAuthenticateOpen] =
        useState(false);
    const [isLegacyOpen, setIsLegacyOpen] = useState(false);
    const [isSupportOpen, setIsSupportOpen] = useState(false);
    const [isSecurityOpen, setIsSecurityOpen] = useState(false);
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
            setIsSecurityOpen(false);
            setIsThemeOpen(false);
        }
    }, [open]);

    return (
        <>
            <LockerSidebarDrawer open={open} onClose={onClose} anchor="left">
                <Stack
                    sx={{ height: "100dvh", minHeight: 0, overflow: "hidden" }}
                >
                    <LockerSidebarTitlebar
                        onClose={onClose}
                        title={userDetails?.email || "Ente Locker"}
                        closeLabel={t("close")}
                        tooltip={userDetails?.email}
                    />
                    <Box
                        sx={{
                            flex: 1,
                            minHeight: 0,
                            overflowY: "auto",
                            overscrollBehavior: "contain",
                            p: "0 16px 24px",
                        }}
                    >
                        {userDetails && (
                            <Box sx={usageCardSx}>
                                <Typography sx={[largeSx, usageMutedSx]}>
                                    {t("itemsStored")}
                                </Typography>
                                <Typography sx={{ ...h1Sx, mt: 0.5 }}>
                                    {formattedUsed}
                                    <Box
                                        component="span"
                                        sx={usageMutedSx}
                                    >{` ${t("of_")} `}</Box>
                                    {formattedMax}
                                </Typography>
                                <Box sx={usageBarSx}>
                                    {showFamilyBreakup && (
                                        <Box
                                            sx={{
                                                width: `${familyProgress * 100}%`,
                                                bgcolor: familyColor,
                                            }}
                                        />
                                    )}
                                    <Box
                                        sx={{
                                            width: `${userProgress * 100}%`,
                                            bgcolor: "accent.main",
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
                                        }}
                                    >
                                        {legendItems.map(({ key, color }) => (
                                            <Stack
                                                key={key}
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
                                                        bgcolor: color,
                                                    }}
                                                />
                                                <Typography
                                                    variant="mini"
                                                    sx={{
                                                        color: familyColor,
                                                        fontWeight: "bold",
                                                    }}
                                                >
                                                    {t(key)}
                                                </Typography>
                                            </Stack>
                                        ))}
                                    </Stack>
                                ) : (
                                    <Box sx={{ height: 16 }} />
                                )}
                            </Box>
                        )}
                        <Stack sx={{ mt: 3, gap: 1 }}>
                            <LockerSidebarCardButton
                                icon={FavouriteIcon}
                                label={t("legacy")}
                                endIcon={<ChevronRightIcon />}
                                onClick={() =>
                                    setIsLegacyAuthenticateOpen(true)
                                }
                            />
                            <Stack direction="row" sx={{ gap: 1 }}>
                                <LockerSidebarCardButton
                                    half
                                    icon={Wallet05Icon}
                                    label={t("menuCollections")}
                                    selected={isCollectionsView}
                                    onClick={onSelectCollections}
                                />
                                <LockerSidebarCardButton
                                    half
                                    icon={Delete02Icon}
                                    label={t("menuTrash")}
                                    selected={isTrashView}
                                    onClick={onSelectTrash}
                                />
                            </Stack>
                        </Stack>
                        <Stack sx={{ mt: 3, gap: 1 }}>
                            <LockerSidebarCardButton
                                icon={UserIcon}
                                label={t("account")}
                                endIcon={<ChevronRightIcon />}
                                onClick={() => setIsAccountOpen(true)}
                            />
                            <LockerSidebarCardButton
                                icon={SecurityCheckIcon}
                                label={t("security")}
                                endIcon={<ChevronRightIcon />}
                                onClick={() => setIsSecurityOpen(true)}
                            />
                            <LockerSidebarCardButton
                                icon={Sun03Icon}
                                label={t("appearance")}
                                endIcon={<ChevronRightIcon />}
                                onClick={() => setIsThemeOpen(true)}
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
                            <LockerSidebarCardButton
                                icon={Logout05Icon}
                                label={t("logout")}
                                endIcon={<ChevronRightIcon />}
                                color="warning"
                                onClick={logout}
                            />
                        </Stack>
                    </Box>
                    <Box sx={{ flexShrink: 0, p: "24px 16px" }}>
                        <LockerSocialFooter />
                    </Box>
                </Stack>
            </LockerSidebarDrawer>
            <LockerSecurityDrawer
                open={isSecurityOpen}
                onClose={() => setIsSecurityOpen(false)}
                onRootClose={onClose}
            />

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
            <LockerThemeDrawer
                open={isThemeOpen}
                onClose={() => setIsThemeOpen(false)}
                onRootClose={onClose}
            />
        </>
    );
};
