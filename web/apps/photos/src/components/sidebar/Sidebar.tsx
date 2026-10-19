import { Export } from "@/components/Export";
import { downloadAppDialogAttributes } from "@/components/utils/download";
import exportService from "@/services/export";
import { performSidebarAction as performSidebarRegistryAction } from "@/services/search/sidebar-search-registry";
import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    Dialog,
    Divider,
    IconButton,
    Stack,
    ThemeProvider,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import Typography from "@mui/material/Typography";
import { isDesktop } from "ente-base/app";
import { LinkButton } from "ente-base/components/LinkButton";
import { AttributedMiniDialog } from "ente-base/components/MiniDialog";
import { RowButtonEndActivityIndicator } from "ente-base/components/RowButton";
import { SpacedRow } from "ente-base/components/containers";
import { SidebarDrawer } from "ente-base/components/mui/SidebarDrawer";
import { SidebarPanelContext } from "ente-base/components/mui/SidebarDrawerContext";
import { useAttributedMiniDialog } from "ente-base/components/utils/dialog";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { photosTheme } from "ente-base/components/utils/theme";
import { RowCard } from "ente-base/components/v2/RowCard";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { customAPIHost } from "ente-base/origins";
import { useUserDetailsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import type { SidebarActionID } from "ente-new/photos/services/search/types";
import {
    hasExceededStorageQuota,
    isFamilyAdmin,
    isPartOfFamily,
    isSubscriptionActive,
    isSubscriptionActivePaid,
    isSubscriptionCancelled,
    isSubscriptionFree,
    isSubscriptionPastDue,
    isSubscriptionStripe,
    pullUserDetails,
    redirectToCustomerPortal,
    userDetailsAddOnBonuses,
    type UserDetails,
} from "ente-new/photos/services/user-details";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import React, {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
    type MouseEventHandler,
} from "react";
import { Trans } from "react-i18next";
import { FreeUpSpace, type FreeUpSpaceAction } from "./FreeUpSpace";
import { Help, type HelpAction } from "./Help";
import { ReferralSettings } from "./ReferralSettings";
import { WatchFolder } from "./WatchFolder";
import { SubscriptionCard } from "./account/SubscriptionCard";
import { Account, type AccountAction } from "./accounts/Account";
import { ManageMemberSubscription } from "./accounts/ManageMemberSubscription";
import { openManageSubscription } from "./accounts/subscription";
import { Preferences, type PreferencesAction } from "./preferences/Preferences";
import { sidebarTheme } from "./theme";

type SidebarProps = ModalVisibilityProps & {
    pendingAction?: SidebarActionID;
    onActionHandled?: (actionID: SidebarActionID) => void;
    onShowLargeFiles: () => void;
    onShowDuplicates: () => void;
    onShowPlanSelector: () => void;
    collectionNameByID: Map<number, string>;
    onCloseOverlays: () => void;
    children?: React.ReactNode;
    onAuthenticateUser: () => Promise<boolean>;
};

export const Sidebar: React.FC<SidebarProps> = ({
    open,
    onClose: closeRoot,
    onCloseOverlays,
    children,
    pendingAction,
    onActionHandled,
    onShowPlanSelector,
    onShowLargeFiles,
    onShowDuplicates,
    collectionNameByID,
    onAuthenticateUser,
}) => {
    const { show: showHelp, props: helpVisibilityProps } = useModalVisibility();
    const { show: showAccount, props: accountVisibilityProps } =
        useModalVisibility();
    const { show: showReferrals, props: referralsVisibilityProps } =
        useModalVisibility();
    const { show: showPreferences, props: preferencesVisibilityProps } =
        useModalVisibility();
    const { show: showFreeUpSpace, props: freeUpSpaceVisibilityProps } =
        useModalVisibility();
    const { show: showExport, props: exportVisibilityProps } =
        useModalVisibility();
    const { onClose: closeExport } = exportVisibilityProps;
    const {
        show: showManageMemberSubscription,
        props: manageMemberSubscriptionVisibilityProps,
    } = useModalVisibility();
    const { onClose: closeMemberSubscription } =
        manageMemberSubscriptionVisibilityProps;

    const { watchFolderView, setWatchFolderView } = usePhotosAppContext();
    const { showMiniDialog, logout } = useBaseContext();
    const {
        showMiniDialog: showDownloadAppDialog,
        miniDialogProps: downloadAppDialogProps,
    } = useAttributedMiniDialog();
    const { onClose: closeDownloadAppDialog } = downloadAppDialogProps;

    useEffect(() => {
        if (!open) {
            closeExport();
            closeMemberSubscription();
            closeDownloadAppDialog();
        }
    }, [open, closeExport, closeMemberSubscription, closeDownloadAppDialog]);

    const [pendingAccountAction, setPendingAccountAction] =
        useState<AccountAction>();
    const [pendingPreferencesAction, setPendingPreferencesAction] =
        useState<PreferencesAction>();
    const [pendingHelpAction, setPendingHelpAction] = useState<HelpAction>();
    const [pendingFreeUpSpaceAction, setPendingFreeUpSpaceAction] =
        useState<FreeUpSpaceAction>();

    const closeSections = useCallback(() => {
        accountVisibilityProps.onClose();
        referralsVisibilityProps.onClose();
        preferencesVisibilityProps.onClose();
        helpVisibilityProps.onClose();
        freeUpSpaceVisibilityProps.onClose();
        closeExport();
        closeMemberSubscription();
        closeDownloadAppDialog();
        setWatchFolderView(false);
        onCloseOverlays();
    }, [
        accountVisibilityProps,
        referralsVisibilityProps,
        preferencesVisibilityProps,
        helpVisibilityProps,
        freeUpSpaceVisibilityProps,
        closeExport,
        closeMemberSubscription,
        closeDownloadAppDialog,
        setWatchFolderView,
        onCloseOverlays,
    ]);

    const onClose = useCallback(() => {
        closeSections();
        closeRoot();
    }, [closeSections, closeRoot]);

    const selectSection = (show: () => void) => () => {
        closeSections();
        show();
    };

    const handleLogout = useCallback(
        () =>
            showMiniDialog({
                message: t("logout_message"),
                kind: "info",
                continue: {
                    text: t("logout"),
                    color: "critical",
                    action: logout,
                },
                buttonDirection: "row",
            }),
        [logout, showMiniDialog],
    );

    const handleOpenWatchFolder = useCallback(
        () => setWatchFolderView(true),
        [setWatchFolderView],
    );

    const handleCloseWatchFolder = useCallback(
        () => setWatchFolderView(false),
        [setWatchFolderView],
    );

    const handleShowExport = useCallback(() => {
        if (!isDesktop) {
            closeMemberSubscription();
            showDownloadAppDialog(downloadAppDialogAttributes());
            return;
        }

        void (async () => {
            try {
                if (!(await onAuthenticateUser())) return;
                closeSections();
                showExport();
            } catch (error) {
                log.error("Failed to authenticate before export", error);
            }
        })();
    }, [
        closeSections,
        closeMemberSubscription,
        onAuthenticateUser,
        showExport,
        showDownloadAppDialog,
    ]);

    const performSidebarAction = useCallback(
        async (actionID: SidebarActionID) => {
            if (actionID !== "utility.export") closeSections();
            return performSidebarRegistryAction(actionID, {
                onClose,
                onShowPlanSelector,
                showAccount,
                showReferrals,
                showPreferences,
                showHelp,
                showFreeUpSpace,
                onShowExport: handleShowExport,
                onLogout: handleLogout,
                onShowWatchFolder: handleOpenWatchFolder,
                setPendingAccountAction: (a) =>
                    setPendingAccountAction(a as AccountAction | undefined),
                setPendingPreferencesAction: (a) =>
                    setPendingPreferencesAction(
                        a as PreferencesAction | undefined,
                    ),
                setPendingHelpAction: (a) =>
                    setPendingHelpAction(a as HelpAction | undefined),
                setPendingFreeUpSpaceAction: (a) =>
                    setPendingFreeUpSpaceAction(
                        a as FreeUpSpaceAction | undefined,
                    ),
            });
        },
        [
            closeSections,
            handleLogout,
            handleOpenWatchFolder,
            onClose,
            onShowPlanSelector,
            handleShowExport,
            showAccount,
            showFreeUpSpace,
            showHelp,
            showPreferences,
            showReferrals,
        ],
    );

    // Closing auth changes these callback identities.
    // Letting that restart the pending action effect would reopen auth.
    const performSidebarActionRef = useRef(performSidebarAction);
    const onActionHandledRef = useRef(onActionHandled);
    useEffect(() => {
        performSidebarActionRef.current = performSidebarAction;
        onActionHandledRef.current = onActionHandled;
    });

    useEffect(() => {
        if (!pendingAction) return;
        void performSidebarActionRef
            .current(pendingAction)
            .finally(() => onActionHandledRef.current?.(pendingAction));
    }, [pendingAction]);

    const hasOpenSection =
        accountVisibilityProps.open ||
        referralsVisibilityProps.open ||
        preferencesVisibilityProps.open ||
        helpVisibilityProps.open ||
        freeUpSpaceVisibilityProps.open ||
        exportVisibilityProps.open ||
        watchFolderView;

    return (
        <RootSidebarDrawer
            open={open}
            onClose={onClose}
            onEnter={pendingAction || hasOpenSection ? undefined : showAccount}
            menu={
                <>
                    <UserDetailsSection
                        sidebarOpen={open}
                        {...{
                            onShowPlanSelector,
                            showManageMemberSubscription,
                            manageMemberSubscriptionVisibilityProps,
                        }}
                    />
                    <Stack
                        sx={{
                            gap: 0.75,
                            "&&& > .MuiButton-root": {
                                my: 0,
                                "&:first-of-type": { mt: 1 },
                                "&:hover": {
                                    bgcolor:
                                        "color-mix(in srgb, var(--mui-palette-text-base) 8%, var(--mui-palette-background-paper))",
                                },
                            },
                        }}
                    >
                        <UtilitySection
                            {...{
                                showExport: handleShowExport,
                                showAccount: selectSection(showAccount),
                                showReferrals: selectSection(showReferrals),
                                showPreferences: selectSection(showPreferences),
                                showHelp: selectSection(showHelp),
                                showFreeUpSpace: selectSection(showFreeUpSpace),
                                onShowWatchFolder: selectSection(
                                    handleOpenWatchFolder,
                                ),
                            }}
                        />
                        <Divider sx={{ mx: 2.5, my: "2px" }} />
                        <ExitSection onLogout={handleLogout} />
                        <InfoSection />
                    </Stack>
                </>
            }
        >
            <AttributedMiniDialog
                {...downloadAppDialogProps}
                appearance="centered"
            />
            {open && exportVisibilityProps.open && (
                <Export
                    {...exportVisibilityProps}
                    collectionNameByID={collectionNameByID}
                    onRootClose={onClose}
                />
            )}
            {helpVisibilityProps.open && (
                <Help
                    {...helpVisibilityProps}
                    onRootClose={onClose}
                    pendingAction={pendingHelpAction}
                    onActionHandled={setPendingHelpAction}
                />
            )}
            {isDesktop && watchFolderView && (
                <WatchFolder
                    open={watchFolderView}
                    onClose={handleCloseWatchFolder}
                    onRootClose={onClose}
                />
            )}
            {accountVisibilityProps.open && (
                <Account
                    {...accountVisibilityProps}
                    onRootClose={onClose}
                    pendingAction={pendingAccountAction}
                    onActionHandled={setPendingAccountAction}
                    {...{ onAuthenticateUser, onShowPlanSelector }}
                />
            )}
            {referralsVisibilityProps.open && (
                <ReferralSettings
                    {...referralsVisibilityProps}
                    onRootClose={onClose}
                />
            )}
            {preferencesVisibilityProps.open && (
                <Preferences
                    {...preferencesVisibilityProps}
                    onRootClose={onClose}
                    pendingAction={pendingPreferencesAction}
                    onActionHandled={setPendingPreferencesAction}
                    onAuthenticateUser={onAuthenticateUser}
                />
            )}
            {freeUpSpaceVisibilityProps.open && (
                <FreeUpSpace
                    onShowLargeFiles={onShowLargeFiles}
                    onShowDuplicates={onShowDuplicates}
                    {...freeUpSpaceVisibilityProps}
                    onRootClose={onClose}
                    pendingAction={pendingFreeUpSpaceAction}
                    onActionHandled={setPendingFreeUpSpaceAction}
                />
            )}
            {children}
        </RootSidebarDrawer>
    );
};

type RootSidebarDrawerProps = React.PropsWithChildren<
    ModalVisibilityProps & { menu: React.ReactNode; onEnter?: () => void }
>;

const RootSidebarDrawer: React.FC<RootSidebarDrawerProps> = (props) => (
    <ThemeProvider theme={sidebarTheme}>
        <RootSidebarContents {...props} />
    </ThemeProvider>
);

function RootSidebarContents({
    open,
    onClose,
    onEnter,
    menu,
    children,
}: RootSidebarDrawerProps) {
    const theme = useTheme();
    const wide = useMediaQuery(theme.breakpoints.up("md"));
    const [panel, setPanel] = useState<HTMLDivElement | null>(null);
    const container = () => panel;

    if (!wide) {
        return (
            <>
                <SidebarDrawer open={open} onClose={onClose} maxWidth="440px">
                    <HeaderSection onCloseSidebar={onClose} />
                    {menu}
                </SidebarDrawer>
                {children}
            </>
        );
    }

    return (
        <Dialog
            open={open}
            onClose={onClose}
            maxWidth={false}
            aria-label={t("settings")}
            slotProps={{
                transition: { onEnter },
                paper: {
                    sx: {
                        width: "min(1200px, calc(100vw - 48px))",
                        maxWidth: "calc(100vw - 48px)",
                        height: "min(900px, calc(100dvh - 48px))",
                        maxHeight: "calc(100dvh - 48px)",
                        m: 3,
                        p: 2,
                        gap: 2,
                        boxSizing: "border-box",
                        borderRadius: 3,
                        bgcolor: "background.default",
                        overflow: "hidden",
                    },
                },
            }}
        >
            <HeaderSection onCloseSidebar={onClose} />
            <SidebarPanelContext.Provider value={container}>
                <ThemeProvider
                    theme={{
                        ...theme,
                        components: {
                            ...theme.components,
                            MuiDialog: {
                                ...theme.components?.MuiDialog,
                                defaultProps: {
                                    ...theme.components?.MuiDialog
                                        ?.defaultProps,
                                    container,
                                    disableEnforceFocus: true,
                                },
                                styleOverrides: {
                                    ...theme.components?.MuiDialog
                                        ?.styleOverrides,
                                    root: [
                                        theme.components?.MuiDialog
                                            ?.styleOverrides?.root,
                                        { position: "absolute" },
                                    ],
                                },
                            },
                            MuiBackdrop: {
                                ...theme.components?.MuiBackdrop,
                                styleOverrides: {
                                    ...theme.components?.MuiBackdrop
                                        ?.styleOverrides,
                                    root: [
                                        theme.components?.MuiBackdrop
                                            ?.styleOverrides?.root,
                                        { position: "absolute" },
                                    ],
                                },
                            },
                        },
                    }}
                >
                    <Box
                        sx={{
                            display: "grid",
                            gridTemplateColumns: "360px minmax(0, 1fr)",
                            gap: 3,
                            flex: 1,
                            minHeight: 0,
                        }}
                    >
                        <Box
                            sx={{
                                overflowY: "auto",
                                "& .MuiDivider-root": {
                                    borderColor: "stroke.muted",
                                },
                            }}
                        >
                            {menu}
                        </Box>
                        <Box
                            ref={setPanel}
                            sx={{
                                position: "relative",
                                minWidth: 0,
                                minHeight: 0,
                                borderRadius: 3,
                                bgcolor: "background.paper2",
                                overflow: "hidden",
                            }}
                        >
                            {/* Wait for the portal target when resizing with a drawer open. */}
                            {panel && children}
                        </Box>
                    </Box>
                </ThemeProvider>
            </SidebarPanelContext.Provider>
        </Dialog>
    );
}

interface SectionProps {
    onCloseSidebar: SidebarProps["onClose"];
}

const HeaderSection: React.FC<SectionProps> = ({ onCloseSidebar }) => (
    <SpacedRow sx={{ mt: { xs: "6px", md: 1 }, pl: "12px", flexShrink: 0 }}>
        <Typography variant="h2" component="h3">
            {t("settings")}
        </Typography>
        <IconButton
            aria-label={t("close")}
            onClick={onCloseSidebar}
            color="primary"
            sx={{
                width: { md: 40 },
                height: { md: 40 },
                bgcolor: { md: "fill.muted" },
            }}
        >
            <CloseIcon fontSize="small" />
        </IconButton>
    </SpacedRow>
);

type UserDetailsSectionProps = Pick<SidebarProps, "onShowPlanSelector"> & {
    sidebarOpen: boolean;
    showManageMemberSubscription: () => void;
    manageMemberSubscriptionVisibilityProps: ModalVisibilityProps;
};

const UserDetailsSection: React.FC<UserDetailsSectionProps> = ({
    sidebarOpen,
    onShowPlanSelector,
    showManageMemberSubscription,
    manageMemberSubscriptionVisibilityProps,
}) => {
    const userDetails = useUserDetailsSnapshot();

    useEffect(() => {
        if (sidebarOpen) void pullUserDetails();
    }, [sidebarOpen]);

    const isNonAdminFamilyMember = useMemo(
        () =>
            userDetails &&
            isPartOfFamily(userDetails) &&
            !isFamilyAdmin(userDetails),
        [userDetails],
    );

    const handleSubscriptionCardClick = () =>
        openManageSubscription({
            userDetails,
            showManageMemberSubscription,
            onShowPlanSelector,
        });

    return (
        <>
            <Box sx={{ px: 0.5, mt: 1.5, pb: 1.5, mb: 1 }}>
                <ThemeProvider theme={photosTheme}>
                    <Box
                        data-sidebar-subscription
                        sx={(theme) => ({
                            "--mui-palette-stroke-base":
                                theme.colorSchemes.light?.palette.stroke.base,
                            "--mui-palette-stroke-faint":
                                theme.colorSchemes.light?.palette.stroke.faint,
                            ...theme.applyStyles("dark", {
                                "--mui-palette-stroke-base":
                                    theme.colorSchemes.dark?.palette.stroke
                                        .base,
                                "--mui-palette-stroke-faint":
                                    theme.colorSchemes.dark?.palette.stroke
                                        .faint,
                            }),
                        })}
                    >
                        <SubscriptionCard
                            userDetails={userDetails}
                            onClick={handleSubscriptionCardClick}
                        />
                    </Box>
                </ThemeProvider>
                {userDetails && (
                    <SubscriptionStatus
                        {...{ userDetails, onShowPlanSelector }}
                    />
                )}
            </Box>
            {isNonAdminFamilyMember && userDetails && (
                <ManageMemberSubscription
                    {...manageMemberSubscriptionVisibilityProps}
                    {...{ userDetails }}
                />
            )}
        </>
    );
};

type SubscriptionStatusProps = Pick<SidebarProps, "onShowPlanSelector"> & {
    userDetails: UserDetails;
};

const SubscriptionStatus: React.FC<SubscriptionStatusProps> = ({
    userDetails,
    onShowPlanSelector,
}) => {
    const hasAMessage = useMemo(() => {
        if (isPartOfFamily(userDetails) && !isFamilyAdmin(userDetails)) {
            return false;
        }
        if (
            isSubscriptionActivePaid(userDetails.subscription) &&
            !isSubscriptionCancelled(userDetails.subscription)
        ) {
            return false;
        }
        return true;
    }, [userDetails]);

    const handleClick: MouseEventHandler<HTMLSpanElement> = useCallback(
        (e) => {
            e.stopPropagation();

            if (isSubscriptionActive(userDetails.subscription)) {
                if (hasExceededStorageQuota(userDetails)) {
                    onShowPlanSelector();
                }
            } else {
                if (
                    isSubscriptionStripe(userDetails.subscription) &&
                    isSubscriptionPastDue(userDetails.subscription)
                ) {
                    // eslint-disable-next-line @typescript-eslint/no-floating-promises
                    redirectToCustomerPortal();
                } else {
                    onShowPlanSelector();
                }
            }
        },
        [onShowPlanSelector, userDetails],
    );

    if (!hasAMessage) {
        return <></>;
    }

    const hasAddOnBonus = userDetailsAddOnBonuses(userDetails).length > 0;

    let message: React.ReactNode;
    if (!hasAddOnBonus) {
        if (isSubscriptionActive(userDetails.subscription)) {
            if (isSubscriptionFree(userDetails.subscription)) {
                message = t("subscription_info_free");
            } else if (isSubscriptionCancelled(userDetails.subscription)) {
                message = t("subscription_info_renewal_cancelled", {
                    date: userDetails.subscription.expiryTime,
                });
            }
        } else {
            message = (
                <Trans
                    i18nKey={"subscription_info_expired"}
                    components={{ a: <LinkButton onClick={handleClick} /> }}
                />
            );
        }
    }

    if (!message && hasExceededStorageQuota(userDetails)) {
        message = (
            <Trans
                i18nKey={"subscription_info_storage_quota_exceeded"}
                components={{ a: <LinkButton onClick={handleClick} /> }}
            />
        );
    }

    if (!message) return <></>;

    return (
        <Box sx={{ px: 1, pt: 0.5 }}>
            <Typography
                variant="small"
                onClick={handleClick}
                sx={{ color: "text.muted" }}
            >
                {message}
            </Typography>
        </Box>
    );
};

interface UtilitySectionProps {
    showExport: () => void;
    showAccount: () => void;
    showReferrals: () => void;
    showPreferences: () => void;
    showHelp: () => void;
    showFreeUpSpace: () => void;
    onShowWatchFolder: () => void;
}

const UtilitySection: React.FC<UtilitySectionProps> = ({
    showExport,
    showAccount,
    showReferrals,
    showPreferences,
    showHelp,
    showFreeUpSpace,
    onShowWatchFolder,
}) => {
    return (
        <>
            <RowCard
                variant="parent"
                title={t("account")}
                onClick={showAccount}
            />
            <RowCard
                variant="parent"
                title={t("referrals")}
                onClick={showReferrals}
            />
            {isDesktop && (
                <RowCard
                    variant="parent"
                    title={t("watch_folders")}
                    onClick={onShowWatchFolder}
                />
            )}
            <RowCard
                variant="parent"
                title={t("free_up_space")}
                onClick={showFreeUpSpace}
            />
            <RowCard
                variant="parent"
                title={t("preferences")}
                onClick={showPreferences}
            />
            <RowCard variant="parent" title={t("help")} onClick={showHelp} />
            <RowCard
                variant="parent"
                title={t("export_data")}
                endIcon={
                    exportService.isExportInProgress() ? (
                        <RowButtonEndActivityIndicator />
                    ) : undefined
                }
                onClick={showExport}
            />
        </>
    );
};

const ExitSection: React.FC<{ onLogout: () => void }> = ({ onLogout }) => (
    <>
        <RowCard
            variant="parent"
            title={
                <Box component="span" sx={{ color: "critical.main" }}>
                    {t("logout")}
                </Box>
            }
            endIcon={null}
            onClick={onLogout}
        />
    </>
);

const InfoSection: React.FC = () => {
    const [host, setHost] = useState<string | undefined>("");

    useEffect(() => {
        void customAPIHost().then(setHost);
    }, []);

    if (!host) return null;

    return (
        <>
            <Stack
                sx={{
                    p: "24px 18px 16px 18px",
                    gap: "24px",
                    color: "text.muted",
                }}
            >
                {host && <Typography variant="mini">{host}</Typography>}
            </Stack>
        </>
    );
};
