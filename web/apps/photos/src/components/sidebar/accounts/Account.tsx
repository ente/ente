import {
    generatePasskeyRecovery,
    recoveryKeyMnemonic,
} from "@/services/recovery-key";
import { Box, Stack } from "@mui/material";
import { RecoveryKey } from "ente-accounts/components/RecoveryKey";
import { updateSavedLocalUser } from "ente-accounts/services/accounts-db";
import { openAccountsManagePasskeysPage } from "ente-accounts/services/passkey";
import { getActiveSessions } from "ente-accounts/services/sessions";
import { isDesktop } from "ente-base/app";
import { EnteSwitch } from "ente-base/components/EnteSwitch";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { RowCard } from "ente-base/components/v2/RowCard";
import { useBaseContext } from "ente-base/context";
import { formattedStorageByteSize } from "ente-gallery/utils/units";
import { useUserDetailsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import {
    reauthenticateWithAppLock,
    suppressAutoLockOnBlurForTrustedPrompt,
} from "ente-new/photos/services/app-lock";
import type { SidebarActionID } from "ente-new/photos/services/search/types";
import { disable2FA, get2FAStatus } from "ente-new/photos/services/user";
import {
    familyMemberStorageLimit,
    isFamilyAdmin,
    isPartOfFamily,
    isPartOfFamilyWithOtherMembers,
    isSubscriptionFree,
    pullUserDetails,
    userDetailsSnapshot,
} from "ente-new/photos/services/user-details";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useMemo, useState } from "react";
import { DeleteAccount } from "../account/DeleteAccount";
import { SessionsSettings } from "../account/SessionsSettings";
import { ManageMemberSubscription } from "./ManageMemberSubscription";
import { openManageSubscription } from "./subscription";

export type AccountAction = Extract<
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

type AccountProps = NestedSidebarDrawerVisibilityProps & {
    onAuthenticateUser: () => Promise<boolean>;
    onShowPlanSelector: () => void;
    pendingAction?: AccountAction;
    onActionHandled?: (action?: AccountAction) => void;
};

export const Account: React.FC<AccountProps> = ({
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
    const [twoFactorEnabled, setTwoFactorEnabled] = useState<boolean>();
    const [disablingTwoFactor, setDisablingTwoFactor] = useState(false);
    const [sessionCount, setSessionCount] = useState<number>();

    let planSubtext: string | undefined;
    if (userDetails) {
        let storage =
            userDetails.subscription.storage + userDetails.storageBonus;

        if (isPartOfFamilyWithOtherMembers(userDetails)) {
            const memberLimit = familyMemberStorageLimit(userDetails);
            const familyStorage =
                (userDetails.familyData?.storage ?? 0) +
                userDetails.storageBonus;
            storage = memberLimit ?? familyStorage;
        }

        const period = userDetails.subscription.period;
        const canShowBillingPeriod =
            !isSubscriptionFree(userDetails.subscription) &&
            (!isPartOfFamily(userDetails) || isFamilyAdmin(userDetails));
        const billingLabel =
            canShowBillingPeriod && period
                ? t(period == "year" ? "yearly" : "monthly")
                : undefined;

        planSubtext = [formattedStorageByteSize(storage), billingLabel]
            .filter(Boolean)
            .join(" · ");
    }

    const router = useRouter();

    const {
        show: showManageMemberSubscription,
        props: manageMemberSubscriptionVisibilityProps,
    } = useModalVisibility();
    const { show: showRecoveryKey, props: recoveryKeyVisibilityProps } =
        useModalVisibility();
    const { show: showSessions, props: sessionsVisibilityProps } =
        useModalVisibility();
    const { show: showDeleteAccount, props: deleteAccountVisibilityProps } =
        useModalVisibility();

    useEffect(() => {
        if (!open || sessionsVisibilityProps.open) return;
        let cancelled = false;
        void Promise.all([
            get2FAStatus().catch(() => undefined),
            getActiveSessions().catch(() => undefined),
        ]).then(([twoFactor, sessions]) => {
            if (cancelled) return;
            setTwoFactorEnabled(twoFactor);
            setSessionCount(sessions?.length);
        });
        return () => {
            cancelled = true;
        };
    }, [open, sessionsVisibilityProps.open]);

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

    const handleChangePassword = useCallback(async () => {
        if (!(await onAuthenticateUser())) return;
        void router.push("/change-password");
    }, [onAuthenticateUser, router]);
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
            if (reauthResult === "fallback" && !(await onAuthenticateUser()))
                return;
        } else {
            if (!(await onAuthenticateUser())) return;
        }
        showRecoveryKey();
    }, [onAuthenticateUser, showRecoveryKey]);

    const handlePasskeys = useCallback(async () => {
        onRootClose();
        if (isDesktop) {
            suppressAutoLockOnBlurForTrustedPrompt();
        }
        await openAccountsManagePasskeysPage(generatePasskeyRecovery);
    }, [onRootClose]);

    const handleActiveSessions = useCallback(async () => {
        if (isDesktop) {
            const reauthResult = await reauthenticateWithAppLock();
            if (reauthResult === "cancelled") return;
            if (reauthResult === "fallback" && !(await onAuthenticateUser()))
                return;
        } else {
            if (!(await onAuthenticateUser())) return;
        }
        showSessions();
    }, [onAuthenticateUser, showSessions]);

    const handleDeleteAccount = useCallback(() => {
        showDeleteAccount();
    }, [showDeleteAccount]);

    const configureTwoFactor = useCallback(() => {
        onClose();
        onRootClose();
        void router.push("/two-factor/setup");
    }, [onClose, onRootClose, router]);

    const handleTwoFactorToggle = useCallback(() => {
        if (twoFactorEnabled === undefined || disablingTwoFactor) return;
        if (!twoFactorEnabled) {
            configureTwoFactor();
            return;
        }
        showMiniDialog({
            title: t("disable_two_factor"),
            message: t("disable_two_factor_message"),
            continue: {
                text: t("disable"),
                color: "critical",
                action: async () => {
                    setDisablingTwoFactor(true);
                    try {
                        await disable2FA();
                        updateSavedLocalUser({ isTwoFactorEnabled: undefined });
                        setTwoFactorEnabled(false);
                    } finally {
                        setDisablingTwoFactor(false);
                    }
                },
            },
        });
    }, [
        twoFactorEnabled,
        disablingTwoFactor,
        configureTwoFactor,
        showMiniDialog,
    ]);

    const handleReconfigureTwoFactor = useCallback(() => {
        showMiniDialog({
            title: t("update_two_factor"),
            message: t("update_two_factor_message"),
            continue: {
                text: t("update"),
                color: "primary",
                action: configureTwoFactor,
            },
        });
    }, [configureTwoFactor, showMiniDialog]);

    useEffect(() => {
        if (!open || !pendingAction) return;
        if (
            pendingAction == "account.twoFactor" &&
            twoFactorEnabled === undefined
        )
            return;
        switch (pendingAction) {
            case "account.subscription":
                handleManageSubscription();
                break;
            case "account.recoveryKey":
                void handleRecoveryKey();
                break;
            case "account.twoFactor.reconfigure":
                handleReconfigureTwoFactor();
                break;
            case "account.twoFactor":
                handleTwoFactorToggle();
                break;
            case "account.passkeys":
                void handlePasskeys();
                break;
            case "account.changePassword":
                void handleChangePassword();
                break;
            case "account.changeEmail":
                handleChangeEmail();
                break;
            case "account.deleteAccount":
                handleDeleteAccount();
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
        handleDeleteAccount,
        handleRecoveryKey,
        handlePasskeys,
        open,
        onActionHandled,
        pendingAction,
        handleReconfigureTwoFactor,
        handleTwoFactorToggle,
        twoFactorEnabled,
    ]);

    return (
        <TitledNestedSidebarDrawer
            maxWidth="440px"
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("account")}
        >
            <Stack sx={{ px: 2, py: 1, gap: 1 }}>
                <RowCard
                    title={t("manage_plan")}
                    subtitle={planSubtext}
                    onClick={handleManageSubscription}
                />
                <RowCard
                    title={t("recovery_key")}
                    onClick={() => void handleRecoveryKey()}
                />
                <RowCard
                    title={t("two_factor")}
                    subtitle={
                        twoFactorEnabled === undefined
                            ? undefined
                            : t(twoFactorEnabled ? "on" : "off")
                    }
                    endIcon={
                        <EnteSwitch
                            checked={twoFactorEnabled === true}
                            disabled={
                                twoFactorEnabled === undefined ||
                                disablingTwoFactor
                            }
                            onChange={handleTwoFactorToggle}
                            slotProps={{
                                input: { "aria-label": t("two_factor") },
                            }}
                        />
                    }
                />
                {twoFactorEnabled && (
                    <RowCard
                        title={t("update_two_factor")}
                        onClick={handleReconfigureTwoFactor}
                    />
                )}
                <RowCard title={t("passkeys")} onClick={handlePasskeys} />
                <RowCard
                    title={t("active_sessions")}
                    subtitle={
                        sessionCount === undefined
                            ? undefined
                            : t("account_sessions", { count: sessionCount })
                    }
                    onClick={handleActiveSessions}
                />
                <RowCard
                    title={t("change_password")}
                    onClick={handleChangePassword}
                />
                <RowCard
                    title={t("change_email")}
                    subtitle={userDetails?.email}
                    onClick={handleChangeEmail}
                />
                <RowCard
                    title={
                        <Box component="span" sx={{ color: "critical.main" }}>
                            {t("delete_account")}
                        </Box>
                    }
                    onClick={handleDeleteAccount}
                />
            </Stack>
            <RecoveryKey
                {...recoveryKeyVisibilityProps}
                getRecoveryKeyMnemonic={recoveryKeyMnemonic}
                {...{ showMiniDialog }}
            />
            {isNonAdminFamilyMember && userDetails && (
                <ManageMemberSubscription
                    {...manageMemberSubscriptionVisibilityProps}
                    {...{ userDetails }}
                />
            )}
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
