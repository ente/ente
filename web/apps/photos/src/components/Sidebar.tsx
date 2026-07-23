import { WatchFolder } from "@/components/WatchFolder";
import {
    Delete02Icon,
    Download05Icon,
    ViewOffSlashIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import CloseIcon from "@mui/icons-material/Close";
import InfoOutlinedIcon from "@mui/icons-material/InfoOutlined";
import LockOutlinedIcon from "@mui/icons-material/LockOutlined";
import NorthEastIcon from "@mui/icons-material/NorthEast";
import {
    Box,
    Dialog,
    DialogContent,
    Divider,
    IconButton,
    Link,
    Skeleton,
    Stack,
    styled,
    TextField,
    Tooltip,
    useColorScheme,
} from "@mui/material";
import Typography from "@mui/material/Typography";
import { RecoveryKey } from "ente-accounts/components/RecoveryKey";
import { openAccountsManagePasskeysPage } from "ente-accounts/services/passkey";
import { isDesktop } from "ente-base/app";
import { EnteLogo, EnteLogoBox } from "ente-base/components/EnteLogo";
import { LinkButton } from "ente-base/components/LinkButton";
import {
    RowButton,
    RowButtonDivider,
    RowButtonEndActivityIndicator,
    RowButtonGroup,
    RowButtonGroupHint,
    RowSwitch,
} from "ente-base/components/RowButton";
import { SpacedRow } from "ente-base/components/containers";
import { DialogCloseIconButton } from "ente-base/components/mui/DialogCloseIconButton";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import {
    SidebarDrawer,
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { isHTTPErrorWithStatus } from "ente-base/http";
import {
    getLocaleInUse,
    setLocaleInUse,
    supportedLocales,
    ut,
    type SupportedLocale,
} from "ente-base/i18n";
import log from "ente-base/log";
import { savedLogs } from "ente-base/log-web";
import { customAPIHost } from "ente-base/origins";
import { saveStringAsFile } from "ente-base/utils/web";
import {
    isHLSGenerationSupported,
    toggleHLSGeneration,
} from "ente-gallery/services/video";
import { DeleteAccount } from "ente-new/photos/components/DeleteAccount";
import { DropdownInput } from "ente-new/photos/components/DropdownInput";
import { ShapeIcon } from "ente-new/photos/components/icons/ShapeIcon";
import { AppLockSettings } from "ente-new/photos/components/sidebar/AppLockSettings";
import { MLSettings } from "ente-new/photos/components/sidebar/MLSettings";
import { SessionsSettings } from "ente-new/photos/components/sidebar/SessionsSettings";
import { TwoFactorSettings } from "ente-new/photos/components/sidebar/TwoFactorSettings";
import { downloadAppDialogAttributes } from "ente-new/photos/components/utils/download";
import {
    useAppLockSnapshot,
    useHLSGenerationStatusSnapshot,
    useSettingsSnapshot,
    useUserDetailsSnapshot,
} from "ente-new/photos/components/utils/use-snapshot";
import {
    reauthenticateWithAppLock,
    suppressAppLockRefreshFromSessionForTrustedReload,
    suppressAutoLockOnBlurForTrustedPrompt,
} from "ente-new/photos/services/app-lock";
import {
    PseudoCollectionID,
    type CollectionSummaries,
} from "ente-new/photos/services/collection-summary";
import exportService from "ente-new/photos/services/export";
import { isMLSupported } from "ente-new/photos/services/ml";
import { performSidebarAction as performSidebarRegistryAction } from "ente-new/photos/services/search/sidebar-search-registry";
import type { SidebarActionID } from "ente-new/photos/services/search/types";
import {
    pullSettings,
    updateCFProxyDisabledPreference,
    updateCustomDomain,
    updateMapEnabled,
} from "ente-new/photos/services/settings";
import {
    familyAdminEmail,
    hasExceededStorageQuota,
    isFamilyAdmin,
    isPartOfFamily,
    isSubscriptionActive,
    isSubscriptionActivePaid,
    isSubscriptionCancelled,
    isSubscriptionFree,
    isSubscriptionPastDue,
    isSubscriptionStripe,
    leaveFamily,
    pullUserDetails,
    redirectToCustomerPortal,
    userDetailsAddOnBonuses,
    userDetailsSnapshot,
    type UserDetails,
} from "ente-new/photos/services/user-details";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { initiateEmail, openURL } from "ente-new/photos/utils/web";
import { wait } from "ente-utils/promise";
import { useFormik } from "formik";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
    type MouseEventHandler,
} from "react";
import { Trans } from "react-i18next";
import { SubscriptionCard } from "./SubscriptionCard";

type SidebarProps = ModalVisibilityProps & {
    /**
     * Information about non-hidden collections and pseudo-collections.
     *
     * These are used to obtain data about the archive, hidden and trash
     * "section" entries shown within the shortcut section of the sidebar.
     */
    normalCollectionSummaries: CollectionSummaries;
    /**
     * The ID of the collection summary that should be shown when the user
     * activates the "Uncategorized" section shortcut.
     */
    uncategorizedCollectionSummaryID: number;

    /**
     * Option search-triggered sidebar action to perform
     */
    pendingAction?: SidebarActionID;

    /**
     * Called after a pending sidebar action has been handled
     */
    onActionHandled?: (actionID: SidebarActionID) => void;
    /**
     * Called when the plan selection modal should be shown.
     */
    onShowPlanSelector: () => void;
    /**
     * Called when the collection summary with the given {@link collectionID}
     * should be shown.
     *
     * @param collectionSummaryID The ID of the {@link CollectionSummary} to
     * switch to.
     *
     * @param isHiddenCollectionSummary If `true`, then any reauthentication as
     * appropriate before switching to the hidden section of the app is
     * performed first before showing the collection summary.
     *
     * @return A promise that fullfills after any needed reauthentication has
     * been peformed (The view transition might still be in progress).
     */
    onShowCollectionSummary: (
        collectionSummaryID: number,
        isHiddenCollectionSummary?: boolean,
    ) => Promise<void>;
    /**
     * Called when the export dialog should be shown.
     */
    onShowExport: () => void;
    /**
     * Called when the user should be authenticated again.
     *
     * This will be invoked before sensitive actions, and the action will only
     * proceed if the promise returned by this function is fulfilled.
     *
     * On errors or if the user cancels the reauthentication, the promise will
     * not settle.
     */
    onAuthenticateUser: () => Promise<void>;
};

type AccountAction = Extract<
    SidebarActionID,
    | "account.subscription"
    | "account.recoveryKey"
    | "account.twoFactor"
    | "account.twoFactor.reconfigure"
    | "account.passkeys"
    | "account.changePassword"
    | "account.changeEmail"
    | "account.deleteAccount"
    | "account.sessions"
>;

type PreferencesAction = Extract<
    SidebarActionID,
    | "preferences.language"
    | "preferences.theme"
    | "preferences.customDomains"
    | "preferences.map"
    | "preferences.fasterUpload"
    | "preferences.openOnStartup"
    | "preferences.advanced"
    | "preferences.mlSearch"
    | "preferences.streamableVideos"
>;

type HelpAction = Extract<
    SidebarActionID,
    | "help.helpCenter"
    | "help.blog"
    | "help.requestFeature"
    | "help.support"
    | "help.viewLogs"
>;

type FreeUpSpaceAction = Extract<
    SidebarActionID,
    "freeUpSpace.deduplicate" | "freeUpSpace.largeFiles"
>;

const appLockReauthenticationCancelledMessage =
    "app_lock_reauthentication_cancelled";

const isReauthenticationCancellation = (error: unknown) =>
    error == undefined ||
    (error instanceof Error &&
        error.message === appLockReauthenticationCancelledMessage);

export const Sidebar: React.FC<SidebarProps> = ({
    open,
    onClose,
    normalCollectionSummaries,
    uncategorizedCollectionSummaryID,
    pendingAction,
    onActionHandled,
    onShowPlanSelector,
    onShowCollectionSummary,
    onShowExport,
    onAuthenticateUser,
}) => {
    const { show: showHelp, props: helpVisibilityProps } = useModalVisibility();
    const { show: showAccount, props: accountVisibilityProps } =
        useModalVisibility();
    const { show: showPreferences, props: preferencesVisibilityProps } =
        useModalVisibility();
    const { show: showFreeUpSpace, props: freeUpSpaceVisibilityProps } =
        useModalVisibility();
    const { watchFolderView, setWatchFolderView } = usePhotosAppContext();
    const { showMiniDialog, logout } = useBaseContext();

    const [pendingAccountAction, setPendingAccountAction] =
        useState<AccountAction>();
    const [pendingPreferencesAction, setPendingPreferencesAction] =
        useState<PreferencesAction>();
    const [pendingHelpAction, setPendingHelpAction] = useState<HelpAction>();
    const [pendingFreeUpSpaceAction, setPendingFreeUpSpaceAction] =
        useState<FreeUpSpaceAction>();

    const handleLogout = useCallback(
        () =>
            showMiniDialog({
                message: t("logout_message"),
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
            showMiniDialog(downloadAppDialogAttributes());
            return;
        }

        void (async () => {
            try {
                await onAuthenticateUser();
                onShowExport();
            } catch {
                // User cancelled reauthentication.
            }
        })();
    }, [onAuthenticateUser, onShowExport, showMiniDialog]);

    const performSidebarAction = useCallback(
        async (actionID: SidebarActionID) =>
            performSidebarRegistryAction(actionID, {
                onClose,
                onShowCollectionSummary,
                onShowPlanSelector,
                showAccount,
                showPreferences,
                showHelp,
                showFreeUpSpace,
                onShowExport: handleShowExport,
                onLogout: handleLogout,
                onShowWatchFolder: handleOpenWatchFolder,
                pseudoIDs: {
                    uncategorized: uncategorizedCollectionSummaryID,
                    archive: PseudoCollectionID.archiveItems,
                    hidden: PseudoCollectionID.hiddenItems,
                    trash: PseudoCollectionID.trash,
                },
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
            }),
        [
            handleLogout,
            handleOpenWatchFolder,
            onClose,
            onShowCollectionSummary,
            onShowPlanSelector,
            handleShowExport,
            showAccount,
            showFreeUpSpace,
            showHelp,
            showPreferences,
            uncategorizedCollectionSummaryID,
        ],
    );

    // Use refs for callbacks to prevent the effect from re-running when
    // callback identities change. This is critical because closing the auth
    // modal causes handleSidebarClose to get a new identity (it depends on
    // authenticateUserVisibilityProps.open), which cascades to
    // performSidebarAction, causing this effect to re-run while pendingAction
    // is still set - reopening the modal.
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

    return (
        <RootSidebarDrawer open={open} onClose={onClose}>
            <HeaderSection onCloseSidebar={onClose} />
            <UserDetailsSection
                sidebarOpen={open}
                {...{ onShowPlanSelector }}
            />
            <Stack sx={{ gap: 0.5, mb: 3 }}>
                <ShortcutSection
                    onCloseSidebar={onClose}
                    {...{
                        normalCollectionSummaries,
                        uncategorizedCollectionSummaryID,
                        onShowCollectionSummary,
                    }}
                />
                <UtilitySection
                    onCloseSidebar={onClose}
                    {...{
                        onShowExport: handleShowExport,
                        onAuthenticateUser,
                        onShowPlanSelector,
                        showAccount,
                        accountVisibilityProps,
                        showPreferences,
                        preferencesVisibilityProps,
                        showHelp,
                        helpVisibilityProps,
                        showFreeUpSpace,
                        freeUpSpaceVisibilityProps,
                        watchFolderView,
                        onShowWatchFolder: handleOpenWatchFolder,
                        onCloseWatchFolder: handleCloseWatchFolder,
                        pendingAccountAction,
                        onAccountActionHandled: setPendingAccountAction,
                        pendingPreferencesAction,
                        onPreferencesActionHandled: setPendingPreferencesAction,
                        pendingHelpAction,
                        onHelpActionHandled: setPendingHelpAction,
                        pendingFreeUpSpaceAction,
                        onFreeUpSpaceActionHandled: setPendingFreeUpSpaceAction,
                    }}
                />
                <Divider sx={{ my: "2px" }} />
                <ExitSection onLogout={handleLogout} />
                <InfoSection />
            </Stack>
        </RootSidebarDrawer>
    );
};

const RootSidebarDrawer = styled(SidebarDrawer)(({ theme }) => ({
    "& .MuiPaper-root": { padding: theme.spacing(1.5) },
}));

interface SectionProps {
    onCloseSidebar: SidebarProps["onClose"];
}

const openManageSubscription = ({
    userDetails,
    showManageMemberSubscription,
    onShowPlanSelector,
}: {
    userDetails: UserDetails | undefined;
    showManageMemberSubscription: () => void;
    onShowPlanSelector: () => void;
}) => {
    if (
        userDetails &&
        isPartOfFamily(userDetails) &&
        !isFamilyAdmin(userDetails)
    ) {
        showManageMemberSubscription();
    } else if (
        userDetails &&
        isSubscriptionStripe(userDetails.subscription) &&
        isSubscriptionPastDue(userDetails.subscription)
    ) {
        // TODO: This makes an API request, so the UI should indicate the await.
        //
        // eslint-disable-next-line @typescript-eslint/no-floating-promises
        redirectToCustomerPortal();
    } else {
        onShowPlanSelector();
    }
};

const HeaderSection: React.FC<SectionProps> = ({ onCloseSidebar }) => (
    <SpacedRow sx={{ mt: "6px", pl: "12px" }}>
        <EnteLogoBox>
            <EnteLogo height={16} />
        </EnteLogoBox>
        <IconButton
            aria-label={t("close")}
            onClick={onCloseSidebar}
            color="secondary"
        >
            <CloseIcon fontSize="small" />
        </IconButton>
    </SpacedRow>
);

type UserDetailsSectionProps = Pick<SidebarProps, "onShowPlanSelector"> & {
    sidebarOpen: boolean;
};

const UserDetailsSection: React.FC<UserDetailsSectionProps> = ({
    sidebarOpen,
    onShowPlanSelector,
}) => {
    const userDetails = useUserDetailsSnapshot();
    const {
        show: showManageMemberSubscription,
        props: manageMemberSubscriptionVisibilityProps,
    } = useModalVisibility();

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
                <Typography sx={{ px: 1, pb: 1, color: "text.muted" }}>
                    {userDetails ? (
                        userDetails.email
                    ) : (
                        <Skeleton animation="wave" />
                    )}
                </Typography>

                <SubscriptionCard
                    userDetails={userDetails}
                    onClick={handleSubscriptionCardClick}
                />
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

type ManageMemberSubscriptionProps = ModalVisibilityProps & {
    userDetails: UserDetails;
};

const ManageMemberSubscription: React.FC<ManageMemberSubscriptionProps> = ({
    open,
    onClose,
    userDetails,
}) => {
    const { showMiniDialog } = useBaseContext();
    const fullScreen = useIsSmallWidth();

    const confirmLeaveFamily = () =>
        showMiniDialog({
            title: t("leave_family_plan"),
            message: t("leave_family_plan_confirm"),
            continue: {
                text: t("leave"),
                color: "critical",
                action: leaveFamily,
            },
        });

    return (
        <Dialog {...{ open, onClose, fullScreen }} maxWidth="xs" fullWidth>
            <SpacedRow sx={{ p: "20px 8px 12px 16px" }}>
                <Stack>
                    <Typography variant="h3">{t("subscription")}</Typography>
                    <Typography sx={{ color: "text.muted" }}>
                        {t("family_plan")}
                    </Typography>
                </Stack>
                <DialogCloseIconButton {...{ onClose }} />
            </SpacedRow>
            <DialogContent>
                <Stack sx={{ alignItems: "center", mx: 2 }}>
                    <Box sx={{ mb: 4 }}>
                        <Typography sx={{ color: "text.muted" }}>
                            {t("subscription_info_family")}
                        </Typography>
                        <Typography>
                            {familyAdminEmail(userDetails) ?? ""}
                        </Typography>
                    </Box>
                    <img
                        height={256}
                        src="/images/family-plan/1x.png"
                        srcSet="/images/family-plan/2x.png 2x, /images/family-plan/3x.png 3x"
                    />
                    <FocusVisibleButton
                        fullWidth
                        variant="outlined"
                        color="critical"
                        onClick={confirmLeaveFamily}
                    >
                        {t("leave_family_plan")}
                    </FocusVisibleButton>
                </Stack>
            </DialogContent>
        </Dialog>
    );
};

type ShortcutSectionProps = SectionProps &
    Pick<
        SidebarProps,
        | "normalCollectionSummaries"
        | "uncategorizedCollectionSummaryID"
        | "onShowCollectionSummary"
    >;

const ShortcutSection: React.FC<ShortcutSectionProps> = ({
    onCloseSidebar,
    normalCollectionSummaries,
    uncategorizedCollectionSummaryID,
    onShowCollectionSummary,
}) => {
    const shortcutIconSize = 20;

    const handleOpenUncategorizedSection = () =>
        void onShowCollectionSummary(uncategorizedCollectionSummaryID).then(
            onCloseSidebar,
        );

    const handleOpenTrashSection = () =>
        void onShowCollectionSummary(PseudoCollectionID.trash).then(
            onCloseSidebar,
        );

    const handleOpenArchiveSection = () =>
        void onShowCollectionSummary(PseudoCollectionID.archiveItems).then(
            onCloseSidebar,
        );

    const handleOpenHiddenSection = () =>
        void onShowCollectionSummary(PseudoCollectionID.hiddenItems, true)
            // See: [Note: Workarounds for unactionable ARIA warnings]
            .then(() => wait(10))
            .then(onCloseSidebar);

    const summaryCaption = (summaryID: number) =>
        normalCollectionSummaries.get(summaryID)?.fileCount.toString();

    return (
        <>
            <RowButton
                startIcon={<ShapeIcon />}
                label={t("section_uncategorized")}
                caption={summaryCaption(uncategorizedCollectionSummaryID)}
                onClick={handleOpenUncategorizedSection}
            />
            <RowButton
                startIcon={
                    <HugeiconsIcon
                        icon={Download05Icon}
                        size={shortcutIconSize}
                    />
                }
                label={t("section_archive")}
                caption={summaryCaption(PseudoCollectionID.archiveItems)}
                onClick={handleOpenArchiveSection}
            />
            <RowButton
                startIcon={
                    <HugeiconsIcon
                        icon={ViewOffSlashIcon}
                        size={shortcutIconSize}
                    />
                }
                label={t("section_hidden")}
                caption={
                    <LockOutlinedIcon
                        sx={{
                            verticalAlign: "middle",
                            fontSize: "19px !important",
                        }}
                    />
                }
                onClick={handleOpenHiddenSection}
            />
            <RowButton
                startIcon={
                    <HugeiconsIcon
                        icon={Delete02Icon}
                        size={shortcutIconSize}
                    />
                }
                label={t("section_trash")}
                caption={summaryCaption(PseudoCollectionID.trash)}
                onClick={handleOpenTrashSection}
            />
        </>
    );
};

type UtilitySectionProps = SectionProps &
    Pick<
        SidebarProps,
        "onShowExport" | "onAuthenticateUser" | "onShowPlanSelector"
    > & {
        showAccount: () => void;
        accountVisibilityProps: ModalVisibilityProps;
        showPreferences: () => void;
        preferencesVisibilityProps: ModalVisibilityProps;
        showHelp: () => void;
        helpVisibilityProps: ModalVisibilityProps;
        showFreeUpSpace: () => void;
        freeUpSpaceVisibilityProps: ModalVisibilityProps;
        watchFolderView: boolean;
        onShowWatchFolder: () => void;
        onCloseWatchFolder: () => void;
        pendingAccountAction?: AccountAction;
        onAccountActionHandled: (action?: AccountAction) => void;
        pendingPreferencesAction?: PreferencesAction;
        onPreferencesActionHandled: (action?: PreferencesAction) => void;
        pendingHelpAction?: HelpAction;
        onHelpActionHandled: (action?: HelpAction) => void;
        pendingFreeUpSpaceAction?: FreeUpSpaceAction;
        onFreeUpSpaceActionHandled: (action?: FreeUpSpaceAction) => void;
    };

const UtilitySection: React.FC<UtilitySectionProps> = ({
    onCloseSidebar,
    onShowExport,
    onAuthenticateUser,
    onShowPlanSelector,
    showAccount,
    accountVisibilityProps,
    showPreferences,
    preferencesVisibilityProps,
    showHelp,
    helpVisibilityProps,
    showFreeUpSpace,
    freeUpSpaceVisibilityProps,
    watchFolderView,
    onShowWatchFolder,
    onCloseWatchFolder,
    pendingAccountAction,
    onAccountActionHandled,
    pendingPreferencesAction,
    onPreferencesActionHandled,
    pendingHelpAction,
    onHelpActionHandled,
    pendingFreeUpSpaceAction,
    onFreeUpSpaceActionHandled,
}) => {
    return (
        <>
            <RowButton
                variant="secondary"
                label={t("account")}
                onClick={showAccount}
            />
            {isDesktop && (
                <RowButton
                    variant="secondary"
                    label={t("watch_folders")}
                    onClick={onShowWatchFolder}
                />
            )}
            <RowButton
                variant="secondary"
                label={t("free_up_space")}
                onClick={showFreeUpSpace}
            />
            <RowButton
                variant="secondary"
                label={t("preferences")}
                onClick={showPreferences}
            />
            <RowButton
                variant="secondary"
                label={t("help")}
                onClick={showHelp}
            />
            <RowButton
                variant="secondary"
                label={t("export_data")}
                endIcon={
                    exportService.isExportInProgress() && (
                        <RowButtonEndActivityIndicator />
                    )
                }
                onClick={onShowExport}
            />
            <Help
                {...helpVisibilityProps}
                onRootClose={onCloseSidebar}
                pendingAction={pendingHelpAction}
                onActionHandled={onHelpActionHandled}
            />
            {isDesktop && (
                <WatchFolder
                    open={watchFolderView}
                    onClose={onCloseWatchFolder}
                />
            )}
            <Account
                {...accountVisibilityProps}
                onRootClose={onCloseSidebar}
                pendingAction={pendingAccountAction}
                onActionHandled={onAccountActionHandled}
                {...{ onAuthenticateUser, onShowPlanSelector }}
            />
            <Preferences
                {...preferencesVisibilityProps}
                onRootClose={onCloseSidebar}
                pendingAction={pendingPreferencesAction}
                onActionHandled={onPreferencesActionHandled}
                onAuthenticateUser={onAuthenticateUser}
            />
            <FreeUpSpace
                {...freeUpSpaceVisibilityProps}
                onRootClose={onCloseSidebar}
                pendingAction={pendingFreeUpSpaceAction}
                onActionHandled={onFreeUpSpaceActionHandled}
            />
        </>
    );
};

const ExitSection: React.FC<{ onLogout: () => void }> = ({ onLogout }) => (
    <>
        <RowButton
            variant="secondary"
            color="critical"
            label={t("logout")}
            onClick={onLogout}
        />
    </>
);

const InfoSection: React.FC = () => {
    const [appVersion, setAppVersion] = useState("");
    const [host, setHost] = useState<string | undefined>("");

    useEffect(() => {
        void globalThis.electron?.appVersion().then(setAppVersion);
        void customAPIHost().then(setHost);
    }, []);

    return (
        <>
            <Stack
                sx={{
                    p: "24px 18px 16px 18px",
                    gap: "24px",
                    color: "text.muted",
                }}
            >
                {appVersion && (
                    <Typography variant="mini">{appVersion}</Typography>
                )}
                {host && <Typography variant="mini">{host}</Typography>}
            </Stack>
        </>
    );
};

type AccountProps = NestedSidebarDrawerVisibilityProps &
    Pick<SidebarProps, "onAuthenticateUser" | "onShowPlanSelector"> & {
        pendingAction?: AccountAction;
        onActionHandled?: (action?: AccountAction) => void;
    };

const Account: React.FC<AccountProps> = ({
    open,
    onClose,
    onRootClose,
    onAuthenticateUser,
    onShowPlanSelector,
    pendingAction,
    onActionHandled,
}) => {
    const { showMiniDialog } = useBaseContext();
    const userDetails = useUserDetailsSnapshot();

    const router = useRouter();

    const {
        show: showManageMemberSubscription,
        props: manageMemberSubscriptionVisibilityProps,
    } = useModalVisibility();
    const { show: showRecoveryKey, props: recoveryKeyVisibilityProps } =
        useModalVisibility();
    const { show: showTwoFactor, props: twoFactorVisibilityProps } =
        useModalVisibility();
    const { show: showSessions, props: sessionsVisibilityProps } =
        useModalVisibility();
    const { show: showDeleteAccount, props: deleteAccountVisibilityProps } =
        useModalVisibility();

    const isNonAdminFamilyMember = useMemo(
        () =>
            userDetails &&
            isPartOfFamily(userDetails) &&
            !isFamilyAdmin(userDetails),
        [userDetails],
    );

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const handleChangePassword = useCallback(() => {
        void router.push("/change-password");
    }, [router]);
    const handleChangeEmail = useCallback(() => {
        void router.push("/change-email");
    }, [router]);

    const handleManageSubscription = useCallback(() => {
        void (async () => {
            if (!userDetails) {
                await pullUserDetails();
            }

            const resolvedUserDetails = userDetails ?? userDetailsSnapshot();
            if (!resolvedUserDetails) return;

            openManageSubscription({
                userDetails: resolvedUserDetails,
                showManageMemberSubscription,
                onShowPlanSelector,
            });
        })();
    }, [onShowPlanSelector, showManageMemberSubscription, userDetails]);

    const handleRecoveryKey = useCallback(async () => {
        if (isDesktop) {
            const reauthResult = await reauthenticateWithAppLock();
            if (reauthResult === "cancelled") return;
            if (reauthResult === "fallback") await onAuthenticateUser();
        } else {
            await onAuthenticateUser();
        }
        showRecoveryKey();
    }, [onAuthenticateUser, showRecoveryKey]);

    const handlePasskeys = useCallback(async () => {
        onRootClose();
        if (isDesktop) {
            suppressAutoLockOnBlurForTrustedPrompt();
        }
        await openAccountsManagePasskeysPage();
    }, [onRootClose]);

    const handleActiveSessions = useCallback(async () => {
        if (isDesktop) {
            const reauthResult = await reauthenticateWithAppLock();
            if (reauthResult === "cancelled") return;
            if (reauthResult === "fallback") await onAuthenticateUser();
        } else {
            await onAuthenticateUser();
        }
        showSessions();
    }, [onAuthenticateUser, showSessions]);

    useEffect(() => {
        if (!open || !pendingAction) return;
        switch (pendingAction) {
            case "account.subscription":
                handleManageSubscription();
                break;
            case "account.recoveryKey":
                void handleRecoveryKey();
                break;
            case "account.twoFactor.reconfigure":
            case "account.twoFactor":
                showTwoFactor();
                break;
            case "account.passkeys":
                void handlePasskeys();
                break;
            case "account.changePassword":
                handleChangePassword();
                break;
            case "account.changeEmail":
                handleChangeEmail();
                break;
            case "account.deleteAccount":
                showDeleteAccount();
                break;
            case "account.sessions":
                void handleActiveSessions();
                break;
        }
        onActionHandled?.();
    }, [
        handleManageSubscription,
        handleActiveSessions,
        handleChangeEmail,
        handleChangePassword,
        handleRecoveryKey,
        handlePasskeys,
        open,
        onActionHandled,
        pendingAction,
        showDeleteAccount,
        showTwoFactor,
    ]);

    return (
        <TitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("account")}
        >
            <Stack sx={{ px: 2, py: 1, gap: 3 }}>
                <RowButtonGroup>
                    <RowButton
                        label={t("manage_plan")}
                        onClick={handleManageSubscription}
                    />
                </RowButtonGroup>
                <RowButtonGroup>
                    <RowButton
                        label={t("recovery_key")}
                        onClick={() => void handleRecoveryKey()}
                    />
                </RowButtonGroup>
                <RowButtonGroup>
                    <RowButton
                        label={t("two_factor")}
                        onClick={showTwoFactor}
                    />
                    <RowButtonDivider />
                    <RowButton label={t("passkeys")} onClick={handlePasskeys} />
                    <RowButtonDivider />
                    <RowButton
                        label={t("active_sessions")}
                        onClick={handleActiveSessions}
                    />
                </RowButtonGroup>
                <RowButtonGroup>
                    <RowButton
                        label={t("change_password")}
                        onClick={handleChangePassword}
                    />
                    <RowButtonDivider />
                    <RowButton
                        label={t("change_email")}
                        onClick={handleChangeEmail}
                    />
                </RowButtonGroup>
                <RowButtonGroup>
                    <RowButton
                        color="critical"
                        label={t("delete_account")}
                        onClick={showDeleteAccount}
                    />
                </RowButtonGroup>
            </Stack>
            <RecoveryKey
                {...recoveryKeyVisibilityProps}
                {...{ showMiniDialog }}
            />
            {isNonAdminFamilyMember && userDetails && (
                <ManageMemberSubscription
                    {...manageMemberSubscriptionVisibilityProps}
                    {...{ userDetails }}
                />
            )}
            <TwoFactorSettings
                {...twoFactorVisibilityProps}
                onRootClose={onRootClose}
            />
            <SessionsSettings
                {...sessionsVisibilityProps}
                onRootClose={onRootClose}
            />
            <DeleteAccount
                {...deleteAccountVisibilityProps}
                {...{ onAuthenticateUser }}
            />
        </TitledNestedSidebarDrawer>
    );
};

const DesktopAppLockSettings: React.FC<
    Pick<SidebarProps, "onAuthenticateUser"> &
        Pick<NestedSidebarDrawerVisibilityProps, "onRootClose">
> = ({ onAuthenticateUser, onRootClose }) => {
    const appLock = useAppLockSnapshot();
    const { show, props } = useModalVisibility();

    const handleOpen = useCallback(async () => {
        try {
            await onAuthenticateUser();
            show();
        } catch (error) {
            if (isReauthenticationCancellation(error)) return;
            log.error("Failed to open app lock settings", error);
        }
    }, [onAuthenticateUser, show]);

    return (
        <>
            <RowButtonGroup>
                <RowButton
                    label={t("app_lock")}
                    caption={
                        !appLock.supported
                            ? t("app_lock_not_supported", {
                                  defaultValue: "App lock is not supported",
                              })
                            : undefined
                    }
                    disabled={!appLock.supported}
                    onClick={handleOpen}
                />
            </RowButtonGroup>
            <AppLockSettings {...props} onRootClose={onRootClose} />
        </>
    );
};

type PreferencesProps = NestedSidebarDrawerVisibilityProps &
    Pick<SidebarProps, "onAuthenticateUser"> & {
        pendingAction?: PreferencesAction;
        onActionHandled?: (action?: PreferencesAction) => void;
    };

const Preferences: React.FC<PreferencesProps> = ({
    open,
    onClose,
    onRootClose,
    onAuthenticateUser,
    pendingAction,
    onActionHandled,
}) => {
    const { show: showDomainSettings, props: domainSettingsVisibilityProps } =
        useModalVisibility();
    const { show: showMapSettings, props: mapSettingsVisibilityProps } =
        useModalVisibility();
    const {
        show: showAdvancedSettings,
        props: advancedSettingsVisibilityProps,
    } = useModalVisibility();
    const { show: showMLSettings, props: mlSettingsVisibilityProps } =
        useModalVisibility();

    const hlsGenStatusSnapshot = useHLSGenerationStatusSnapshot();
    const isHLSGenerationEnabled = !!hlsGenStatusSnapshot?.enabled;

    useEffect(() => {
        if (open) void pullSettings();
    }, [open]);

    useEffect(() => {
        if (!open || !pendingAction) return;
        switch (pendingAction) {
            case "preferences.customDomains":
                showDomainSettings();
                break;
            case "preferences.map":
                showMapSettings();
                break;
            case "preferences.advanced":
            case "preferences.fasterUpload":
            case "preferences.openOnStartup":
                showAdvancedSettings();
                break;
            case "preferences.mlSearch":
                showMLSettings();
                break;
            case "preferences.language":
            case "preferences.theme":
            case "preferences.streamableVideos":
                break;
        }
        onActionHandled?.();
    }, [
        open,
        onActionHandled,
        pendingAction,
        showAdvancedSettings,
        showDomainSettings,
        showMLSettings,
        showMapSettings,
    ]);

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    return (
        <TitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("preferences")}
        >
            <Stack sx={{ px: 2, py: 1, gap: 3 }}>
                <LanguageSelector />
                <ThemeSelector />
                <Divider sx={{ my: "2px", opacity: 0.1 }} />
                {isMLSupported && (
                    <RowButtonGroup>
                        <RowButton
                            endIcon={<ChevronRightIcon />}
                            label={t("ml_search")}
                            onClick={showMLSettings}
                        />
                    </RowButtonGroup>
                )}
                <RowButton
                    label={t("custom_domains")}
                    endIcon={<ChevronRightIcon />}
                    onClick={showDomainSettings}
                />
                <RowButton
                    endIcon={<ChevronRightIcon />}
                    label={t("map")}
                    onClick={showMapSettings}
                />
                <RowButton
                    endIcon={<ChevronRightIcon />}
                    label={t("advanced")}
                    onClick={showAdvancedSettings}
                />
                {isDesktop && (
                    <DesktopAppLockSettings
                        onAuthenticateUser={onAuthenticateUser}
                        onRootClose={onRootClose}
                    />
                )}
                {isHLSGenerationSupported && (
                    <RowButtonGroup>
                        <RowSwitch
                            label={t("streamable_videos")}
                            checked={isHLSGenerationEnabled}
                            onClick={() => void toggleHLSGeneration()}
                        />
                    </RowButtonGroup>
                )}
            </Stack>
            <DomainSettings
                {...domainSettingsVisibilityProps}
                onRootClose={onRootClose}
            />
            <MapSettings
                {...mapSettingsVisibilityProps}
                onRootClose={onRootClose}
            />
            <AdvancedSettings
                {...advancedSettingsVisibilityProps}
                onRootClose={onRootClose}
            />
            <MLSettings
                {...mlSettingsVisibilityProps}
                onRootClose={handleRootClose}
            />
        </TitledNestedSidebarDrawer>
    );
};

const LanguageSelector = () => {
    const locale = getLocaleInUse();

    const updateCurrentLocale = (newLocale: SupportedLocale) => {
        if (newLocale === locale) return;

        void setLocaleInUse(newLocale).then(() => {
            // [Note: Changing locale causes a full reload]
            //
            // A full reload is needed because we use the global `t` instance
            // instead of the useTranslation hook.
            //
            // We also rely on this behaviour by caching various formatters in
            // module static variables that not get updated if the i18n.language
            // changes unless there is a full reload.
            //
            // Mark this as a trusted app-initiated reload so desktop app-lock
            // setup does not force an immediate lock screen.
            if (globalThis.electron) {
                suppressAppLockRefreshFromSessionForTrustedReload();
            }
            window.location.reload();
        });
    };

    const options = supportedLocales.map((locale) => ({
        label: localeName(locale),
        value: locale,
    }));

    return (
        <Stack sx={{ gap: 1 }}>
            <Typography variant="small" sx={{ px: 1, color: "text.muted" }}>
                {t("language")}
            </Typography>
            <DropdownInput
                options={options}
                selected={locale}
                onSelect={updateCurrentLocale}
            />
        </Stack>
    );
};

/**
 * Human readable name for each supported locale.
 */
const localeName = (locale: SupportedLocale) => {
    switch (locale) {
        case "en-US":
            return "English";
        case "fr-FR":
            return "Français";
        case "de-DE":
            return "Deutsch";
        case "ca-ES":
            return "Català";
        case "zh-CN":
            return "简体中文";
        case "zh-TW":
            return "繁體中文";
        case "nl-NL":
            return "Nederlands";
        case "es-ES":
            return "Español";
        case "pt-PT":
            return "Português";
        case "pt-BR":
            return "Português Brasileiro";
        case "ru-RU":
            return "Русский";
        case "pl-PL":
            return "Polski";
        case "it-IT":
            return "Italiano";
        case "lt-LT":
            return "Lietuvių kalba";
        case "uk-UA":
            return "Українська";
        case "ur-IN":
            return "اردو";
        case "vi-VN":
            return "Tiếng Việt";
        case "ja-JP":
            return "日本語";
        case "ar-SA":
            return "اَلْعَرَبِيَّةُ";
        case "tr-TR":
            return "Türkçe";
        case "cs-CZ":
            return "čeština";
        case "el-GR":
            return "Ελληνικά";
    }
};

const ThemeSelector = () => {
    const { mode, setMode } = useColorScheme();

    // During SSR, mode is always undefined.
    if (!mode) return null;

    return (
        <Stack sx={{ gap: 1 }}>
            <Typography variant="small" sx={{ px: 1, color: "text.muted" }}>
                {t("theme")}
            </Typography>
            <DropdownInput
                options={[
                    { label: t("system"), value: "system" },
                    { label: t("light"), value: "light" },
                    { label: t("dark"), value: "dark" },
                ]}
                selected={mode}
                onSelect={setMode}
            />
        </Stack>
    );
};

const DomainSettings: React.FC<NestedSidebarDrawerVisibilityProps> = ({
    open,
    onClose,
    onRootClose,
}) => {
    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    return (
        <TitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("custom_domains")}
            caption={t("custom_domains_desc")}
        >
            <DomainSettingsContents />
        </TitledNestedSidebarDrawer>
    );
};

// Separate component to reset state on going back.
const DomainSettingsContents: React.FC = () => {
    const { customDomain, customDomainCNAME } = useSettingsSnapshot();

    const formik = useFormik({
        initialValues: { domain: customDomain ?? "" },
        onSubmit: async (values, { setFieldError }) => {
            const domain = values.domain;
            const setValueFieldError = (message: string) =>
                setFieldError("domain", message);

            try {
                await updateCustomDomain(domain);
            } catch (e) {
                log.error(`Failed to submit input ${domain}`, e);
                if (isHTTPErrorWithStatus(e, 400)) {
                    setValueFieldError(t("invalid_domain"));
                } else if (isHTTPErrorWithStatus(e, 402)) {
                    setValueFieldError(t("sharing_disabled_for_free_accounts"));
                } else if (isHTTPErrorWithStatus(e, 409)) {
                    setValueFieldError(t("already_linked_domain"));
                } else {
                    setValueFieldError(t("generic_error"));
                }
            }
        },
    });

    return (
        <Stack sx={{ px: 2, py: "12px" }}>
            <DomainItem title={t("link_your_domain")} ordinal={t("num_1")}>
                <form onSubmit={formik.handleSubmit}>
                    <TextField
                        name="domain"
                        value={formik.values.domain}
                        onChange={formik.handleChange}
                        type={"text"}
                        fullWidth
                        autoFocus={true}
                        margin="dense"
                        disabled={formik.isSubmitting}
                        error={!!formik.errors.domain}
                        helperText={formik.errors.domain ?? t("domain_help")}
                        label={t("domain")}
                        placeholder={ut("photos.example.org")}
                        sx={{ mb: 2 }}
                    />
                    <LoadingButton
                        fullWidth
                        type="submit"
                        loading={formik.isSubmitting}
                        color="accent"
                    >
                        {customDomain ? t("update") : t("save")}
                    </LoadingButton>
                </form>
            </DomainItem>
            <Divider sx={{ mt: 4, mb: 2, opacity: 0.5 }} />
            <DomainItem title={t("add_dns_entry")} ordinal={t("num_2")}>
                <Typography sx={{ color: "text.muted" }}>
                    <Trans
                        i18nKey="add_dns_entry_hint"
                        components={{
                            b: (
                                <Typography
                                    component="span"
                                    sx={{
                                        fontWeight: "bold",
                                        color: "text.base",
                                    }}
                                />
                            ),
                        }}
                        values={{ host: customDomainCNAME }}
                    />
                </Typography>
                <Typography sx={{ color: "text.muted", mt: 3 }}>
                    <Trans
                        i18nKey="custom_domains_help"
                        components={{
                            a: (
                                <Link
                                    href="https://ente.com/help/photos/features/sharing-and-collaboration/custom-domains/"
                                    target="_blank"
                                    rel="noopener"
                                    color="accent"
                                />
                            ),
                        }}
                    />
                </Typography>
            </DomainItem>
        </Stack>
    );
};

interface DomainSectionProps {
    title: string;
    ordinal: string;
}

const DomainItem: React.FC<React.PropsWithChildren<DomainSectionProps>> = ({
    title,
    ordinal,
    children,
}) => (
    <Stack>
        <Stack
            direction="row"
            sx={{ alignItems: "center", justifyContent: "space-between" }}
        >
            <Typography variant="h6">{title}</Typography>
            <Typography
                variant="h1"
                sx={{
                    minWidth: "28px",
                    textAlign: "center",
                    color: "stroke.faint",
                }}
            >
                {ordinal}
            </Typography>
        </Stack>
        {children}
    </Stack>
);

const MapSettings: React.FC<NestedSidebarDrawerVisibilityProps> = ({
    open,
    onClose,
    onRootClose,
}) => {
    const { mapEnabled } = useSettingsSnapshot();
    const [errorMessage, setErrorMessage] = useState<string | undefined>();

    const handleToggle = useCallback(() => {
        setErrorMessage(undefined);
        void updateMapEnabled(!mapEnabled).catch(() => {
            setErrorMessage(t("generic_error"));
        });
    }, [mapEnabled]);

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    return (
        <TitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("map")}
        >
            <Stack sx={{ px: 2, py: "20px" }}>
                <RowButtonGroup>
                    <RowSwitch
                        label={t("enabled")}
                        checked={mapEnabled}
                        onClick={handleToggle}
                    />
                </RowButtonGroup>
                <RowButtonGroupHint>
                    {t("maps_privacy_notice")}
                </RowButtonGroupHint>
                {errorMessage && (
                    <Typography
                        variant="small"
                        sx={{
                            color: "critical.main",
                            mt: 0.5,
                            textAlign: "center",
                        }}
                    >
                        {errorMessage}
                    </Typography>
                )}
            </Stack>
        </TitledNestedSidebarDrawer>
    );
};

const AdvancedSettings: React.FC<NestedSidebarDrawerVisibilityProps> = ({
    open,
    onClose,
    onRootClose,
}) => {
    const { cfUploadProxyDisabled } = useSettingsSnapshot();
    const [isAutoLaunchEnabled, setIsAutoLaunchEnabled] = useState(false);

    const electron = globalThis.electron;

    const refreshAutoLaunchEnabled = useCallback(async () => {
        return electron
            ?.isAutoLaunchEnabled()
            .then((enabled) => setIsAutoLaunchEnabled(enabled));
    }, [electron]);

    useEffect(
        () => void refreshAutoLaunchEnabled(),
        [refreshAutoLaunchEnabled],
    );

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const toggleProxy = () =>
        void updateCFProxyDisabledPreference(!cfUploadProxyDisabled);

    const toggleAutoLaunch = () =>
        void electron?.toggleAutoLaunch().then(refreshAutoLaunchEnabled);

    return (
        <TitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("advanced")}
        >
            <Stack sx={{ px: 2, py: "20px", gap: 3 }}>
                <Stack>
                    <RowButtonGroup>
                        <RowSwitch
                            label={t("faster_upload")}
                            checked={!cfUploadProxyDisabled}
                            onClick={toggleProxy}
                        />
                    </RowButtonGroup>
                    <RowButtonGroupHint>
                        {t("faster_upload_description")}
                    </RowButtonGroupHint>
                </Stack>
                {electron && (
                    <RowButtonGroup>
                        <RowSwitch
                            label={t("open_ente_on_startup")}
                            checked={isAutoLaunchEnabled}
                            onClick={toggleAutoLaunch}
                        />
                    </RowButtonGroup>
                )}
            </Stack>
        </TitledNestedSidebarDrawer>
    );
};

type HelpProps = NestedSidebarDrawerVisibilityProps & {
    pendingAction?: HelpAction;
    onActionHandled?: (Action?: HelpAction) => void;
};

const Help: React.FC<HelpProps> = ({
    open,
    onClose,
    onRootClose,
    pendingAction,
    onActionHandled,
}) => {
    const { showMiniDialog } = useBaseContext();

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const handleHelp = useCallback(
        () => openURL("https://ente.com/help/photos/"),
        [],
    );

    const handleBlog = useCallback(() => openURL("https://ente.com/blog/"), []);

    const handleRequestFeature = useCallback(
        () => openURL("https://github.com/ente/ente/discussions"),
        [],
    );

    const handleSupport = useCallback(
        () => initiateEmail("support@ente.com"),
        [],
    );

    const viewLogs = useCallback(async () => {
        log.info("Viewing logs");
        const electron = globalThis.electron;
        if (electron) {
            await electron.openLogDirectory();
        } else {
            saveStringAsFile(savedLogs(), `ente-web-logs-${Date.now()}.txt`);
        }
    }, []);

    const confirmViewLogs = useCallback(
        () =>
            showMiniDialog({
                title: t("view_logs"),
                message: <Trans i18nKey={"view_logs_message"} />,
                continue: { text: t("view_logs"), action: viewLogs },
            }),
        [showMiniDialog, viewLogs],
    );

    useEffect(() => {
        if (!open || !pendingAction) return;
        switch (pendingAction) {
            case "help.helpCenter":
                handleHelp();
                break;
            case "help.blog":
                handleBlog();
                break;
            case "help.requestFeature":
                handleRequestFeature();
                break;
            case "help.support":
                handleSupport();
                break;
            case "help.viewLogs":
                confirmViewLogs();
                break;
        }
        onActionHandled?.();
    }, [
        confirmViewLogs,
        handleBlog,
        handleHelp,
        handleRequestFeature,
        handleSupport,
        open,
        onActionHandled,
        pendingAction,
    ]);

    return (
        <TitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("help")}
        >
            <Stack sx={{ px: 2, py: 1, gap: 3 }}>
                <RowButtonGroup>
                    <RowButton
                        endIcon={<InfoOutlinedIcon />}
                        label={t("ente_help")}
                        onClick={handleHelp}
                    />
                </RowButtonGroup>
                <RowButtonGroup>
                    <RowButton
                        endIcon={<NorthEastIcon />}
                        label={t("blog")}
                        onClick={handleBlog}
                    />
                    <RowButtonDivider />
                    <RowButton
                        endIcon={<NorthEastIcon />}
                        label={t("request_feature")}
                        onClick={handleRequestFeature}
                    />
                </RowButtonGroup>
                <RowButtonGroup>
                    <RowButton
                        endIcon={<ChevronRightIcon />}
                        label={
                            <Tooltip title="support@ente.com">
                                <Typography sx={{ fontWeight: "medium" }}>
                                    {t("support")}
                                </Typography>
                            </Tooltip>
                        }
                        onClick={handleSupport}
                    />
                </RowButtonGroup>
                <RowButtonGroup>
                    <RowButton
                        endIcon={<ChevronRightIcon />}
                        label={t("view_logs")}
                        onClick={confirmViewLogs}
                    />
                </RowButtonGroup>
            </Stack>
        </TitledNestedSidebarDrawer>
    );
};

type FreeUpSpaceProps = NestedSidebarDrawerVisibilityProps & {
    pendingAction?: FreeUpSpaceAction;
    onActionHandled?: (action?: FreeUpSpaceAction) => void;
};

const FreeUpSpace: React.FC<FreeUpSpaceProps> = ({
    open,
    onClose,
    onRootClose,
    pendingAction,
    onActionHandled,
}) => {
    const router = useRouter();

    const handleRootClose = useCallback(() => {
        onClose();
        onRootClose();
    }, [onClose, onRootClose]);

    const handleDeduplicate = useCallback(() => {
        onRootClose();
        void router.push("/duplicates");
    }, [onRootClose, router]);

    const handleLargeFiles = useCallback(() => {
        onRootClose();
        void router.push("/large-files");
    }, [onRootClose, router]);

    useEffect(() => {
        if (!open || !pendingAction) return;
        switch (pendingAction) {
            case "freeUpSpace.deduplicate":
                handleDeduplicate();
                break;
            case "freeUpSpace.largeFiles":
                handleLargeFiles();
                break;
        }
        onActionHandled?.();
    }, [
        handleDeduplicate,
        handleLargeFiles,
        open,
        onActionHandled,
        pendingAction,
    ]);

    return (
        <TitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("free_up_space")}
        >
            <Stack sx={{ px: 2, py: 1, gap: 3 }}>
                <RowButtonGroup>
                    <RowButton
                        label={t("deduplicate_files")}
                        onClick={handleDeduplicate}
                    />
                    <RowButtonDivider />
                    <RowButton
                        label={t("large_files_title")}
                        onClick={handleLargeFiles}
                    />
                </RowButtonGroup>
            </Stack>
        </TitledNestedSidebarDrawer>
    );
};
